import AVFoundation
import Combine
import Foundation

/// Records only explicitly initiated sessions into the store's app-owned drafts directory.
/// A draft is left on disk until the caller imports it successfully or explicitly cancels it.
@MainActor
final class CaptureRecorder: NSObject, ObservableObject {
    enum State: String { case idle, requestingPermission, recording, paused, failed }
    enum Permission: String {
        case notDetermined, authorized, denied, restricted
        var nextStep: String? {
            switch self {
            case .denied: return "Allow Pip Capture in System Settings → Privacy & Security → Microphone, then try again."
            case .restricted: return "Microphone access is restricted on this Mac. Ask its administrator to allow access."
            default: return nil
            }
        }
    }
    struct RecordingResult { let url: URL; let duration: TimeInterval }
    enum RecorderError: LocalizedError {
        case permission(String), invalidState, startFailed, missingDraft, recordingFailed(String)
        var errorDescription: String? {
            switch self {
            case .permission(let message): return message
            case .invalidState: return "There is no active recording for this action."
            case .startFailed: return "The microphone could not start recording. Check the selected input device and try again."
            case .missingDraft: return "The recording draft is missing. Existing drafts have been preserved."
            case .recordingFailed(let message): return "Recording failed: \(message). The draft is retained for recovery."
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var permission: Permission
    @Published private(set) var meter: Float = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: String?
    @Published private(set) var draftURL: URL?
    private let draftsDirectory: URL
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var permissionGeneration = UUID()

    init(draftsDirectory: URL) {
        self.draftsDirectory = draftsDirectory.standardizedFileURL
        self.permission = Self.currentPermission()
        super.init()
    }

    func refreshPermission() { permission = Self.currentPermission() }

    /// Call from an explicit user gesture. Construction and app launch never request access.
    func requestPermissionAndStart() async throws {
        guard state == .idle || (state == .failed && draftURL == nil) else { throw RecorderError.invalidState }
        refreshPermission()
        let generation = UUID()
        permissionGeneration = generation
        if permission == .notDetermined {
            state = .requestingPermission
            _ = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in continuation.resume(returning: granted) }
            }
            // A late OS callback must never restart a cancelled session.
            guard permissionGeneration == generation, !Task.isCancelled else {
                if permissionGeneration == generation { state = .idle }
                throw CancellationError()
            }
            refreshPermission()
            state = .idle
        }
        guard !Task.isCancelled else { throw CancellationError() }
        try start()
    }

    /// Starts only with an already granted OS permission.
    func start() throws {
        guard state == .idle || (state == .failed && draftURL == nil) else { throw RecorderError.invalidState }
        refreshPermission()
        guard permission == .authorized else {
            let failure = RecorderError.permission(permission.nextStep ?? "Choose Record to request microphone access.")
            lastError = failure.localizedDescription
            throw failure
        }
        lastError = nil
        duration = 0
        do {
            try FileManager.default.createDirectory(at: draftsDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let url = draftsDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
            draftURL = url
            let session = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            session.delegate = self
            session.isMeteringEnabled = true
            recorder = session
            guard session.prepareToRecord(), session.record() else { throw RecorderError.startFailed }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            state = .recording
            startMeter()
        } catch {
            fail(error)
            throw error
        }
    }

    func pause() throws {
        guard state == .recording, let recorder else { throw RecorderError.invalidState }
        duration = recorder.currentTime
        recorder.pause()
        stopMeter()
        state = .paused
    }

    func resume() throws {
        guard state == .paused, let recorder else { throw RecorderError.invalidState }
        guard recorder.record() else {
            let error = RecorderError.startFailed
            fail(error)
            throw error
        }
        state = .recording
        startMeter()
    }

    func stop() throws -> RecordingResult {
        guard state == .recording || state == .paused, let session = recorder, let url = draftURL else {
            throw RecorderError.invalidState
        }
        session.delegate = nil
        session.stop()
        recorder = nil
        stopMeter()
        guard FileManager.default.fileExists(atPath: url.path) else {
            fail(RecorderError.missingDraft)
            throw RecorderError.missingDraft
        }
        let elapsed: TimeInterval
        do {
            let saved = try AVAudioFile(forReading: url)
            guard saved.length > 0, saved.processingFormat.sampleRate > 0 else {
                throw RecorderError.recordingFailed("No audio frames were written")
            }
            elapsed = Double(saved.length) / saved.processingFormat.sampleRate
        } catch {
            fail(error)
            throw error
        }
        duration = elapsed
        state = .idle
        // Ownership transfers to the caller. The original stays on disk if import fails.
        draftURL = nil
        return RecordingResult(url: url, duration: elapsed)
    }

    /// Deletes only the current UUID draft. It never sweeps the draft directory.
    func cancel() throws {
        permissionGeneration = UUID()
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        stopMeter()
        if let url = draftURL {
            guard url.deletingLastPathComponent().standardizedFileURL == draftsDirectory,
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  url.pathExtension == "m4a" else { throw RecorderError.missingDraft }
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } catch {
                fail(error)
                throw error
            }
        }
        draftURL = nil
        duration = 0
        lastError = nil
        state = .idle
    }

    /// Leaves a failed session's draft untouched for the library recovery flow.
    /// This cannot interrupt active recording or dismiss a pending OS grant.
    /// Returning the URL transfers recovery ownership without reading, moving or
    /// deleting the file; a failed start may have produced no file at that URL.
    @discardableResult func keepDraftAndReset() throws -> URL? {
        guard state == .failed else { throw RecorderError.invalidState }
        let retained = draftURL
        if let retained {
            guard retained.deletingLastPathComponent().standardizedFileURL == draftsDirectory,
                  UUID(uuidString: retained.deletingPathExtension().lastPathComponent) != nil,
                  retained.pathExtension == "m4a" else { throw RecorderError.missingDraft }
        }
        permissionGeneration = UUID()
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        stopMeter()
        draftURL = nil
        duration = 0
        lastError = nil
        state = .idle
        return retained
    }

    private static func currentPermission() -> Permission {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }

    private func startMeter() {
        stopMeter()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .recording, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.meter = min(1, max(0, pow(10, recorder.averagePower(forChannel: 0) / 20)))
                self.duration = recorder.currentTime
            }
        }
        meterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMeter() { meterTimer?.invalidate(); meterTimer = nil; meter = 0 }
    private func fail(_ error: Error) {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        stopMeter()
        lastError = error.localizedDescription
        state = .failed
    }
}

extension CaptureRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.fail(RecorderError.recordingFailed(flag ? "The input ended unexpectedly" : "The audio device stopped before saving"))
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.fail(RecorderError.recordingFailed(error?.localizedDescription ?? "Audio encoding failed"))
        }
    }
}
