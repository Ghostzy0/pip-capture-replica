import AVFoundation
import Foundation
import Darwin
import XCTest
@testable import PipCapture

final class LocalTranscriberTests: XCTestCase {
    func testMillisecondOffsetsAndOriginalWords() throws {
        let json = Data(#"{"result":{"language":"en"},"transcription":[{"offsets":{"from":1250,"to":2750},"text":" Do not send £19.50 to Alice. "}]}"#.utf8)
        let result = try LocalTranscriber.parse(json)
        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].start, 1.25)
        XCTAssertEqual(result.segments[0].end, 2.75)
        XCTAssertEqual(result.segments[0].text, "Do not send £19.50 to Alice.")
    }

    func testOlderTimestampFormat() throws {
        let json = Data(#"{"transcription":[{"timestamps":{"from":"01:02:03,400","to":"01:02:05.900"},"text":"Hello"}]}"#.utf8)
        let result = try LocalTranscriber.parse(json)
        XCTAssertEqual(result.segments[0].start, 3723.4, accuracy: 0.001)
        XCTAssertEqual(result.segments[0].end, 3725.9, accuracy: 0.001)
    }

    func testMalformedAndReversedTimestampsRejected() throws {
        for json in [#"{}"#, #"{"transcription":[{"offsets":{"from":2000,"to":1000},"text":"wrong"}]}"#,
                     #"{"transcription":[{"timestamps":{"from":"00:99:01","to":"00:99:02"},"text":"wrong"}]}"#] {
            XCTAssertThrowsError(try LocalTranscriber.parse(Data(json.utf8)))
        }
    }

    func testSilenceCanReturnNoSegments() throws {
        let result = try LocalTranscriber.parse(Data(#"{"transcription":[]}"#.utf8))
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testMissingToolAndModelAreDistinct() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let noTool = LocalTranscriber(configuration: .init(executableURL: missing, modelURL: missing))
        do { _ = try await noTool.transcribe(audioURL: missing); XCTFail("Must reject missing tool") }
        catch LocalTranscriber.TranscriptionError.missingTool { }
        let noModel = LocalTranscriber(configuration: .init(executableURL: URL(fileURLWithPath: "/usr/bin/true"), modelURL: missing))
        do { _ = try await noModel.transcribe(audioURL: missing); XCTFail("Must reject missing model") }
        catch LocalTranscriber.TranscriptionError.missingModel { }
    }

    /// This exercises AVFoundation conversion through the process boundary without a model download.
    /// `true` is deliberately not a recogniser, so the final result must reject its absent JSON.
    func testConversionRetainsOriginalAndRejectsMissingTranscript() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.wav")
        let model = root.appendingPathComponent("fixture-model.bin")
        try Data("synthetic model marker".utf8).write(to: model)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100))
        buffer.frameLength = 44_100
        for channel in 0..<2 {
            let samples = try XCTUnwrap(buffer.floatChannelData?[channel])
            for frame in 0..<44_100 { samples[frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44_100)) * 0.2 }
        }
        // Explicitly close/finalise the fixture before reopening it for conversion.
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: source, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        XCTAssertEqual(try AVAudioFile(forReading: source).length, 44_100)
        let original = try Data(contentsOf: source)
        let worker = LocalTranscriber(configuration: .init(executableURL: URL(fileURLWithPath: "/usr/bin/true"), modelURL: model))
        do { _ = try await worker.transcribe(audioURL: source); XCTFail("Must reject absent output") }
        catch LocalTranscriber.TranscriptionError.invalidOutput { }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    @MainActor func testCancellingIdleRecorderCannotRemoveOtherDrafts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("\(UUID().uuidString).m4a")
        let original = Data("recoverable draft".utf8)
        try original.write(to: other)
        let recorder = CaptureRecorder(draftsDirectory: root)
        XCTAssertEqual(recorder.state, .idle)
        try recorder.cancel()
        XCTAssertEqual(try Data(contentsOf: other), original)
    }

    @MainActor func testKeepDraftRecoveryRefusesIdleAndPreservesExistingDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("\(UUID().uuidString).m4a")
        let original = Data("retained recovery source".utf8)
        try original.write(to: source)
        let recorder = CaptureRecorder(draftsDirectory: root)
        XCTAssertThrowsError(try recorder.keepDraftAndReset()) { error in
            guard let recorderError = error as? CaptureRecorder.RecorderError,
                  case .invalidState = recorderError else {
                return XCTFail("Recovery must refuse a recorder outside its failed state")
            }
        }
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertNil(recorder.draftURL)
        XCTAssertNil(recorder.lastError)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testConfiguredWorkspaceCleanedOnSuccessAndFailure() async throws {
        let fixture = try makeProcessFixture(delayed: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = try Data(contentsOf: fixture.audio)
        let worker = LocalTranscriber(configuration: .init(executableURL: fixture.tool, modelURL: fixture.model, workspaceDirectory: fixture.work))
        let result = try await worker.transcribe(audioURL: fixture.audio)
        XCTAssertEqual(result.text, "Late fixture result")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.work.path), [])
        let permissions = try FileManager.default.attributesOfItem(atPath: fixture.work.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
        // The fixture records its actual cwd: conversion and JSON were inside app work.
        let usedPath = try String(contentsOf: fixture.model.appendingPathExtension("workspace"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let usedURL = URL(fileURLWithPath: usedPath)
        XCTAssertEqual(usedURL.deletingLastPathComponent().resolvingSymlinksInPath().path, fixture.work.resolvingSymlinksInPath().path)
        XCTAssertTrue(usedURL.lastPathComponent.hasPrefix("pip-capture-asr-"))
        let failure = LocalTranscriber(configuration: .init(executableURL: URL(fileURLWithPath: "/usr/bin/false"), modelURL: fixture.model, workspaceDirectory: fixture.work))
        do { _ = try await failure.transcribe(audioURL: fixture.audio); XCTFail("Must reject failing CLI") }
        catch LocalTranscriber.TranscriptionError.failed { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.work.path), [])
        XCTAssertEqual(try Data(contentsOf: fixture.audio), original)
    }

    func testCancellationTerminatesWorkerAndRejectsItsLateResult() async throws {
        let fixture = try makeProcessFixture(delayed: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let worker = LocalTranscriber(configuration: .init(executableURL: fixture.tool, modelURL: fixture.model, timeout: 10, workspaceDirectory: fixture.work))
        let task = Task { try await worker.transcribe(audioURL: fixture.audio) }
        defer { task.cancel() }
        try await waitUntilStarted(fixture.model)
        await worker.cancel()
        do { _ = try await task.value; XCTFail("Must reject late result after cancellation") }
        catch LocalTranscriber.TranscriptionError.cancelled { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.work.path), [])
        try assertWorkerExited(fixture.model)
        // A cancelled actor session must also release its busy state, and Swift
        // Task cancellation must stop the replacement worker through its handler.
        try FileManager.default.removeItem(at: fixture.model.appendingPathExtension("started"))
        let replacement = Task { try await worker.transcribe(audioURL: fixture.audio) }
        defer { replacement.cancel() }
        try await waitUntilStarted(fixture.model)
        replacement.cancel()
        do { _ = try await replacement.value; XCTFail("Must reject late result after Task cancellation") }
        catch LocalTranscriber.TranscriptionError.cancelled { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.work.path), [])
        try assertWorkerExited(fixture.model)
    }

    func testTimeoutTerminatesWorkerAndRejectsItsLateResult() async throws {
        let fixture = try makeProcessFixture(delayed: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let worker = LocalTranscriber(configuration: .init(executableURL: fixture.tool, modelURL: fixture.model, timeout: 0.25, workspaceDirectory: fixture.work))
        do { _ = try await worker.transcribe(audioURL: fixture.audio); XCTFail("Must reject late result after timeout") }
        catch LocalTranscriber.TranscriptionError.timedOut { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.model.appendingPathExtension("started").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.work.path), [])
        try assertWorkerExited(fixture.model)
    }

    func testExplicitCleanupOnlyRemovesMarkedUUIDDirectories() throws {
        let fixture = try makeProcessFixture(delayed: false)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.work, withIntermediateDirectories: true)
        let id = UUID()
        let owned = fixture.work.appendingPathComponent("pip-capture-asr-\(id.uuidString)")
        try fm.createDirectory(at: owned, withIntermediateDirectories: false)
        XCTAssertEqual(Darwin.kill(Int32.max, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        let staleMarker = try JSONSerialization.data(withJSONObject: ["workspaceID": id.uuidString, "ownerPID": Int32.max, "phase": "preparing"])
        try staleMarker.write(to: owned.appendingPathComponent(".pip-capture-workspace"))
        try Data("derived copy".utf8).write(to: owned.appendingPathComponent("input.wav"))
        let liveID = UUID()
        let live = fixture.work.appendingPathComponent("pip-capture-asr-\(liveID.uuidString)")
        try fm.createDirectory(at: live, withIntermediateDirectories: false)
        try JSONSerialization.data(withJSONObject: ["workspaceID": liveID.uuidString, "ownerPID": getpid()])
            .write(to: live.appendingPathComponent(".pip-capture-workspace"))
        // A crashed parent is insufficient: the child might still be transcribing.
        let orphanID = UUID()
        let orphan = fixture.work.appendingPathComponent("pip-capture-asr-\(orphanID.uuidString)")
        try fm.createDirectory(at: orphan, withIntermediateDirectories: false)
        try JSONSerialization.data(withJSONObject: ["workspaceID": orphanID.uuidString, "ownerPID": Int32.max, "phase": "running", "workerPID": getpid()])
            .write(to: orphan.appendingPathComponent(".pip-capture-workspace"))
        let gapID = UUID()
        let gap = fixture.work.appendingPathComponent("pip-capture-asr-\(gapID.uuidString)")
        try fm.createDirectory(at: gap, withIntermediateDirectories: false)
        try JSONSerialization.data(withJSONObject: ["workspaceID": gapID.uuidString, "ownerPID": Int32.max, "phase": "launching"])
            .write(to: gap.appendingPathComponent(".pip-capture-workspace"))
        let unrelated = fixture.work.appendingPathComponent("pip-capture-asr-\(UUID().uuidString)")
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: false)
        let link = fixture.work.appendingPathComponent("pip-capture-asr-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: fixture.root)
        XCTAssertEqual(try LocalTranscriber.workspaceCopies(in: fixture.work).map { $0.resolvingSymlinksInPath().path }, [owned.resolvingSymlinksInPath().path])
        XCTAssertEqual(try LocalTranscriber.cleanupWorkspaceCopies(in: fixture.work), 1)
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
        XCTAssertTrue(fm.fileExists(atPath: link.path))
        XCTAssertTrue(fm.fileExists(atPath: live.path))
        XCTAssertTrue(fm.fileExists(atPath: orphan.path))
        XCTAssertTrue(fm.fileExists(atPath: gap.path))
        XCTAssertTrue(fm.fileExists(atPath: fixture.audio.path))
        XCTAssertThrowsError(try LocalTranscriber.cleanupWorkspaceCopies(in: link))
    }

    private struct ProcessFixture { let root: URL; let audio: URL; let model: URL; let tool: URL; let work: URL }

    /// Explicit local /bin/sh fixture only; the application never invokes a shell.
    /// It writes a valid late result when terminated to exercise stale-result rejection.
    private func makeProcessFixture(delayed: Bool) throws -> ProcessFixture {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("capture-audio-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let model = root.appendingPathComponent("fixture-model.bin")
        let audio = root.appendingPathComponent("original.wav")
        let tool = root.appendingPathComponent("fixture-cli")
        let work = root.appendingPathComponent("work")
        try Data("fixture only".utf8).write(to: model)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for frame in 0..<1_600 { samples[frame] = 0 }
        try autoreleasepool {
            let file = try AVAudioFile(forWriting: audio, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        let script = """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -m) model="$2"; shift 2 ;;
            -of) out="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        emit_result() {
          printf '%s' '{"transcription":[{"offsets":{"from":0,"to":100},"text":"Late fixture result"}]}' > "$out.json"
        }
        printf '%s' "$$" > "$model.pid"
        pwd > "$model.workspace"
        trap 'emit_result; exit 0' TERM
        printf ready > "$model.started"
        \(delayed ? "while :; do /bin/sleep 0.05; done" : "emit_result")
        """
        try Data(script.utf8).write(to: tool)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        return ProcessFixture(root: root, audio: audio, model: model, tool: tool, work: work)
    }

    private func waitUntilStarted(_ model: URL) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: model.appendingPathExtension("started").path) {
            guard Date() < deadline else { throw LocalTranscriber.TranscriptionError.failed("Fixture did not start") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func assertWorkerExited(_ model: URL) throws {
        let pidText = try String(contentsOf: model.appendingPathExtension("pid"), encoding: .utf8)
        let pid = try XCTUnwrap(Int32(pidText))
        XCTAssertEqual(Darwin.kill(pid, 0), -1, "Fixture process must have exited before transcription completes")
        XCTAssertEqual(errno, ESRCH)
    }
}
