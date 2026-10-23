import AVFoundation
import CaptureCore
import Darwin
import Foundation

/// Original local process integration, informed by WhisperNotes' MIT-licensed
/// WhisperService at 05d12535863757943a7e243edd2df7cea1d86f84.
/// Uses a configured whisper.cpp CLI and model; never downloads or uploads audio.
actor LocalTranscriber {
    struct Configuration: Sendable {
        let executableURL: URL
        let modelURL: URL
        var language: String = "auto"
        var timeout: TimeInterval = 300
        /// GUI callers supply their app-owned work directory so crash leftovers
        /// remain visible to the app's documented retention/cleanup controls.
        /// CLI callers that omit it use an owner-only OS temporary child.
        var workspaceDirectory: URL? = nil
    }
    struct TranscriptionResult: Sendable {
        let text: String
        let segments: [TranscriptSegment]
        let provenance: String
    }
    enum TranscriptionError: LocalizedError {
        case missingTool, missingModel, invalidAudio(String), cancelled, timedOut, busy, failed(String), invalidOutput
        var errorDescription: String? {
            switch self {
            case .missingTool: return "Choose an executable local whisper.cpp whisper-cli in Settings. Nothing has been downloaded."
            case .missingModel: return "Choose an existing compatible whisper.cpp model in Settings. Nothing has been downloaded."
            case .invalidAudio(let reason): return "This audio could not be read: \(reason). The original has been retained."
            case .cancelled: return "Transcription cancelled. The original audio is retained."
            case .timedOut: return "Local transcription timed out. Try a smaller model or a shorter recording."
            case .busy: return "A local transcription is already running."
            case .failed(let reason): return "Local transcription failed: \(reason)"
            case .invalidOutput: return "The local tool did not produce a valid timestamped whisper.cpp JSON transcript."
            }
        }
    }

    private let configuration: Configuration
    private var current: (id: UUID, control: TranscriptionControl)?
    init(configuration: Configuration) { self.configuration = configuration }

    func cancel() { current?.control.stop(.cancelled) }

    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard current == nil else { throw TranscriptionError.busy }
        let id = UUID()
        let control = TranscriptionControl()
        current = (id, control)
        let configuration = configuration
        defer { if current?.id == id { current = nil } }
        return try await withTaskCancellationHandler {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.perform(audioURL: audioURL, configuration: configuration, control: control)
            }.value
            try control.check()
            guard !Task.isCancelled, current?.id == id else { throw TranscriptionError.cancelled }
            return result
        } onCancel: { control.stop(.cancelled) }
    }

    private static func perform(audioURL: URL, configuration: Configuration, control: TranscriptionControl) throws -> TranscriptionResult {
        try control.check()
        let fm = FileManager.default
        guard configuration.executableURL.isFileURL,
              fm.isExecutableFile(atPath: configuration.executableURL.path) else { throw TranscriptionError.missingTool }
        var isDirectory: ObjCBool = false
        guard configuration.modelURL.isFileURL,
              fm.fileExists(atPath: configuration.modelURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue, fm.isReadableFile(atPath: configuration.modelURL.path) else { throw TranscriptionError.missingModel }
        guard configuration.timeout.isFinite, configuration.timeout > 0 else {
            throw TranscriptionError.failed("The timeout must be greater than zero.")
        }
        let workspaceRoot = configuration.workspaceDirectory ?? fm.temporaryDirectory
        try prepareWorkspaceRoot(workspaceRoot)
        let workspaceID = UUID()
        let working = workspaceRoot.appendingPathComponent("pip-capture-asr-\(workspaceID.uuidString)", isDirectory: true)
        try fm.createDirectory(at: working, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: working) }
        let markerURL = working.appendingPathComponent(".pip-capture-workspace")
        let marker = WorkspaceMarker(workspaceID: workspaceID, ownerPID: getpid(), phase: "preparing", workerPID: nil)
        try JSONEncoder().encode(marker).write(to: markerURL, options: .atomic)
        let converted = working.appendingPathComponent("input.wav")
        try convert(audioURL: audioURL, destination: converted, control: control)
        try control.check()

        let outputBase = working.appendingPathComponent("transcript")
        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = ["-m", configuration.modelURL.path, "-f", converted.path,
                             "-l", configuration.language, "-oj", "-of", outputBase.path, "-np"]
        process.currentDirectoryURL = working
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        let stderr = BoundedTranscriptionLog()
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = (try? handle.read(upToCount: 8_192)) ?? Data()
            if !data.isEmpty { stderr.append(data) }
        }
        defer {
            errors.fileHandleForReading.readabilityHandler = nil
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        // Conservatively mark the spawn gap before launching. A crash in that gap
        // leaves an uncertain workspace that explicit cleanup must preserve.
        try JSONEncoder().encode(WorkspaceMarker(workspaceID: workspaceID, ownerPID: getpid(), phase: "launching", workerPID: nil)).write(to: markerURL, options: .atomic)
        do { try control.launch(process) }
        catch let error as TranscriptionError { throw error }
        catch { throw TranscriptionError.failed(error.localizedDescription) }
        // If this update fails, the launching marker remains conservative.
        try? JSONEncoder().encode(WorkspaceMarker(workspaceID: workspaceID, ownerPID: getpid(), phase: "running", workerPID: process.processIdentifier)).write(to: markerURL, options: .atomic)
        let timeout = DispatchWorkItem { control.stop(.timedOut) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + configuration.timeout, execute: timeout)
        process.waitUntilExit()
        timeout.cancel()
        control.finished()
        try control.check()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let detail = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriptionError.failed("Tool exited with status \(process.terminationStatus). \(detail)")
        }
        let outputURL = outputBase.appendingPathExtension("json")
        guard let size = try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 32 * 1_024 * 1_024, let data = try? Data(contentsOf: outputURL) else { throw TranscriptionError.invalidOutput }
        let parsed = try parse(data)
        try control.check()
        return TranscriptionResult(text: parsed.segments.map(\.text).joined(separator: " "), segments: parsed.segments,
                                   provenance: "Local whisper.cpp (\(configuration.executableURL.lastPathComponent)); model: \(configuration.modelURL.lastPathComponent); language: \(parsed.language ?? configuration.language); source: retained original audio; 16 kHz mono PCM transcription copy; \(ISO8601DateFormatter().string(from: Date()))")
    }

    /// Preview only app-created, marked immediate children with demonstrably dead
    /// owner PIDs. No recursive search,
    /// symlink following or deletion of similarly named unrelated directories.
    /// Call only against the application's work directory, with no active job.
    static func workspaceCopies(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard directory.isFileURL else { throw TranscriptionError.failed("The transcription workspace must be a local directory.") }
        if !fm.fileExists(atPath: directory.path) {
            // fileExists follows links; lstat also catches a broken root symlink.
            var info = stat()
            guard directory.path.withCString({ lstat($0, &info) }) != 0 else {
                throw TranscriptionError.failed("The transcription workspace cannot be a symbolic link.")
            }
            return []
        }
        try validateWorkspaceRoot(directory)
        let candidates = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        return try candidates.filter(isOwnedWorkspace).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Explicit owner-confirmed cleanup of derived work copies, never the root
    /// or retained audio. The caller must ensure there is no active transcription.
    @discardableResult static func cleanupWorkspaceCopies(in directory: URL) throws -> Int {
        let copies = try workspaceCopies(in: directory)
        var removed = 0
        for copy in copies {
            // Revalidate immediately before deletion rather than using an old preview.
            try validateWorkspaceRoot(directory)
            guard try isOwnedWorkspace(copy) else { continue }
            try FileManager.default.removeItem(at: copy)
            removed += 1
        }
        return removed
    }

    private static func isOwnedWorkspace(_ candidate: URL) throws -> Bool {
        let prefix = "pip-capture-asr-"
        guard candidate.lastPathComponent.hasPrefix(prefix),
              let id = UUID(uuidString: String(candidate.lastPathComponent.dropFirst(prefix.count))) else { return false }
        let values = try candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { return false }
        let marker = candidate.appendingPathComponent(".pip-capture-workspace")
        guard let markerValues = try? marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              markerValues.isRegularFile == true, markerValues.isSymbolicLink != true,
              let size = markerValues.fileSize, size > 0, size <= 1_024,
              let contents = try? Data(contentsOf: marker),
              let ownership = try? JSONDecoder().decode(WorkspaceMarker.self, from: contents),
              ownership.workspaceID == id, ownership.ownerPID > 0 else { return false }
        // Another Pip instance may own this directory. Unknown permission state
        // and reused PIDs are treated as live; only ESRCH proves a dead owner.
        guard Darwin.kill(ownership.ownerPID, 0) == -1 && errno == ESRCH else { return false }
        switch ownership.phase {
        case "preparing": return ownership.workerPID == nil
        case "running":
            guard let worker = ownership.workerPID, worker > 0 else { return false }
            return Darwin.kill(worker, 0) == -1 && errno == ESRCH
        default: return false // Legacy/uncertain launch state requires manual inspection.
        }
    }

    private struct WorkspaceMarker: Codable {
        let workspaceID: UUID
        let ownerPID: Int32
        let phase: String?
        let workerPID: Int32?
    }

    private static func validateWorkspaceRoot(_ directory: URL) throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directory.isFileURL, values.isDirectory == true, values.isSymbolicLink != true else {
            throw TranscriptionError.failed("The transcription workspace must be a local directory, not a symbolic link.")
        }
    }

    private static func prepareWorkspaceRoot(_ directory: URL) throws {
        guard directory.isFileURL else { throw TranscriptionError.failed("The transcription workspace must be local.") }
        let fm = FileManager.default
        var info = stat()
        let exists = directory.path.withCString { lstat($0, &info) } == 0
        if exists { try validateWorkspaceRoot(directory) }
        else { try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        // Never change permissions on the system temp root; only its private child.
        if directory.standardizedFileURL != fm.temporaryDirectory.standardizedFileURL {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    /// Streams a conversion copy, avoiding a full recording-sized allocation.
    private static func convert(audioURL: URL, destination: URL, control: TranscriptionControl) throws {
        guard audioURL.isFileURL else { throw TranscriptionError.invalidAudio("Choose a local audio file") }
        do {
            let source = try AVAudioFile(forReading: audioURL)
            guard source.length > 0, source.processingFormat.channelCount > 0,
                  source.processingFormat.sampleRate > 0,
                  let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: source.processingFormat, to: target),
                  let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4_096),
                  let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4_096) else {
                throw TranscriptionError.invalidAudio("The file has no decodable audio frames")
            }
            let destinationFile = try AVAudioFile(forWriting: destination, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            var reachedEnd = false
            var readError: Error?
            var written: AVAudioFramePosition = 0
            while true {
                try control.check()
                var conversionError: NSError?
                let status = converter.convert(to: output, error: &conversionError) { requested, outStatus in
                    if reachedEnd { outStatus.pointee = .endOfStream; return nil }
                    do {
                        // AVAudioFile can report eofErr (-39) when read is asked for
                        // frames beyond its actual end. Tell the converter EOF before
                        // making that read, and clamp the final partial input buffer.
                        let remaining = source.length - source.framePosition
                        guard remaining > 0 else { reachedEnd = true; outStatus.pointee = .endOfStream; return nil }
                        let count = min(min(requested, input.frameCapacity), AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max))))
                        try source.read(into: input, frameCount: count)
                        if input.frameLength == 0 { reachedEnd = true; outStatus.pointee = .endOfStream; return nil }
                        outStatus.pointee = .haveData
                        return input
                    } catch {
                        readError = error
                        reachedEnd = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                }
                if let readError { throw readError }
                if let conversionError { throw conversionError }
                if status == .error { throw TranscriptionError.invalidAudio("Audio conversion failed") }
                if output.frameLength > 0 { try destinationFile.write(from: output); written += AVAudioFramePosition(output.frameLength) }
                if status == .endOfStream { break }
            }
            guard written > 0 else { throw TranscriptionError.invalidAudio("The file has no audio frames") }
        } catch let error as TranscriptionError { throw error }
        catch { throw TranscriptionError.invalidAudio(error.localizedDescription) }
    }

    /// whisper.cpp JSON uses millisecond offsets; timestamps are accepted for older CLIs.
    static func parse(_ data: Data) throws -> (segments: [TranscriptSegment], language: String?) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["transcription"] as? [[String: Any]] else { throw TranscriptionError.invalidOutput }
        var segments: [TranscriptSegment] = []
        for entry in entries {
            guard let text = entry["text"] as? String else { throw TranscriptionError.invalidOutput }
            let offsets = entry["offsets"] as? [String: NSNumber]
            let timestamps = entry["timestamps"] as? [String: String]
            let start = offsets?["from"].map { $0.doubleValue / 1_000 } ?? timestamps?["from"].flatMap(parseTimestamp)
            let end = offsets?["to"].map { $0.doubleValue / 1_000 } ?? timestamps?["to"].flatMap(parseTimestamp)
            guard let start, let end, start.isFinite, end.isFinite, start >= 0, end >= start else {
                throw TranscriptionError.invalidOutput
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { segments.append(TranscriptSegment(start: start, end: end, text: trimmed)) }
        }
        return (segments, (root["result"] as? [String: Any])?["language"] as? String)
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]),
              hours >= 0, minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else { return nil }
        return hours * 3_600 + minutes * 60 + seconds
    }
}

/// Synchronous cancellation state closes the launch/cancel race even before run() returns.
private final class TranscriptionControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var reason: LocalTranscriber.TranscriptionError?
    func check() throws {
        lock.lock(); let value = reason; lock.unlock()
        if let value { throw value }
    }
    func launch(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if let reason { throw reason }
        try process.run()
        self.process = process
    }
    func finished() { lock.lock(); process = nil; lock.unlock() }
    func stop(_ reason: LocalTranscriber.TranscriptionError) {
        lock.lock()
        if self.reason == nil { self.reason = reason }
        let running = process
        lock.unlock()
        guard let running, running.isRunning else { return }
        running.terminate()
        // A misbehaving local CLI must not keep a cancelled task alive indefinitely.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if running.isRunning { _ = Darwin.kill(running.processIdentifier, SIGKILL) }
        }
    }
}

private final class BoundedTranscriptionLog: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 16_384 { data.removeFirst(data.count - 16_384) }
    }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
