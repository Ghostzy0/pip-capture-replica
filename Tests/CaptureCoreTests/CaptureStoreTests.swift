import Foundation
import Darwin
import XCTest
@testable import CaptureCore

@_silgen_name("flock") private func captureTestFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

final class CaptureStoreTests: XCTestCase {
    private var root: URL!
    private var store: CaptureStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-tests-" + UUID().uuidString)
        store = CaptureStore(directory: root.appendingPathComponent("library"))
        try store.load()
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func source(_ name: String, data: Data = Data([0, 1, 2, 3, 255])) throws -> URL {
        let url = root.appendingPathComponent(name); try data.write(to: url); return url
    }

    func testTextCRUDReopenAndFiltersPreserveSourceProvenance() throws {
        var note = try store.createNote(title: "Budget", body: "Do not spend £900", tags: [" Work ", "work", "Budget"], folder: "Plans")
        note.favourite = true; note.originalTranscript = "Do not spend £900"
        let segment = TranscriptSegment(start: 1.25, end: 4.5, text: "Do not spend £900")
        note.segments = [segment]; note.transcriptionEngine = "Local synthetic fixture"
        try store.save(note)
        XCTAssertEqual(store.filteredNotes(query: "£900", folder: "Plans", tag: "Work", favouritesOnly: true).count, 1)
        XCTAssertEqual(store.notes[0].tags, ["Work", "Budget"])
        var edited = store.notes[0]; edited.body = "Budget amended"; try store.save(edited)
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        XCTAssertEqual(reopened.notes[0].body, "Budget amended")
        XCTAssertEqual(reopened.notes[0].originalTranscript, "Do not spend £900")
        XCTAssertEqual(reopened.notes[0].segments, [segment])
        XCTAssertEqual(reopened.notes[0].transcriptionEngine, "Local synthetic fixture")
        XCTAssertEqual(reopened.notes[0].createdAt.timeIntervalSince1970, note.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMalformedIndexPreservedAndWritesBlocked() throws {
        let data = Data("{ broken index".utf8); try data.write(to: store.indexURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertTrue($0.localizedDescription.contains("preserved")) }
        XCTAssertThrowsError(try store.createNote(body: "Do not overwrite corruption"))
        XCTAssertEqual(try Data(contentsOf: store.indexURL), data)
        XCTAssertNotNil(store.lastError)
    }

    func testUnsupportedVersionAndUnsafeAudioIndexArePreserved() throws {
        _ = try store.createNote(title: "Safe")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.indexURL)) as? [String: Any])
        object["version"] = 99
        var data = try JSONSerialization.data(withJSONObject: object); try data.write(to: store.indexURL)
        XCTAssertThrowsError(try store.load()); XCTAssertEqual(try Data(contentsOf: store.indexURL), data)
        object["version"] = 1
        var notes = try XCTUnwrap(object["notes"] as? [[String: Any]])
        notes[0]["audioFilename"] = "../../outside.wav"; object["notes"] = notes
        data = try JSONSerialization.data(withJSONObject: object); try data.write(to: store.indexURL)
        XCTAssertThrowsError(try store.load()); XCTAssertEqual(try Data(contentsOf: store.indexURL), data)
    }

    func testFailedSaveLeavesMemoryAndPreviousIndexUnchanged() throws {
        let note = try store.createNote(body: "Original")
        let backup = root.appendingPathComponent("old-index.json")
        try FileManager.default.moveItem(at: store.indexURL, to: backup)
        try FileManager.default.createDirectory(at: store.indexURL, withIntermediateDirectories: false)
        var changed = note; changed.body = "Should not persist"
        XCTAssertThrowsError(try store.save(changed))
        XCTAssertEqual(store.note(id: note.id)?.body, "Original")
        XCTAssertNotNil(store.lastError)
        try FileManager.default.removeItem(at: store.indexURL)
        try FileManager.default.moveItem(at: backup, to: store.indexURL)
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        XCTAssertEqual(reopened.notes[0].body, "Original")
    }

    func testAudioBytesAreRetainedAndExportNeverOverwrites() throws {
        let bytes = Data([0, 255, 8, 9, 0, 10])
        let original = try source("original.wav", data: bytes)
        let note = try store.importAudio(from: original, title: "../../Unsafe: title\n---")
        let retained = try XCTUnwrap(store.audioURL(for: note))
        XCTAssertNotEqual(retained, original)
        XCTAssertEqual(try Data(contentsOf: retained), bytes)
        XCTAssertNotNil(UUID(uuidString: retained.deletingPathExtension().lastPathComponent))
        let destination = root.appendingPathComponent("exports"); try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let exported = try store.exportAudio(noteID: note.id, to: destination)
        XCTAssertEqual(exported.deletingLastPathComponent().standardizedFileURL.path, destination.standardizedFileURL.path)
        XCTAssertEqual(try Data(contentsOf: exported), bytes)
        XCTAssertThrowsError(try store.exportAudio(noteID: note.id, to: destination))
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertThrowsError(try store.attachAudio(to: note.id, from: original))
    }

    func testSafeTextImportAndYAMLExport() throws {
        let original = try source("memo.md", data: Data("Names: Alex. Number: 14. Do not delete.".utf8))
        var note = try store.importText(from: original)
        note.title = "../quote\"\n---\nfolder: injected"
        note.tags = ["a\"\nb", "#yes"]; note.folder = "x\n---"
        note.originalTranscript = "Source text"; note.segments = [TranscriptSegment(start: 0, end: 2, text: "Source text")]
        try store.save(note)
        let exported = try store.exportMarkdown(noteID: note.id, to: root)
        XCTAssertEqual(exported.deletingLastPathComponent().standardizedFileURL.path, root.standardizedFileURL.path)
        let text = try String(contentsOf: exported, encoding: .utf8)
        XCTAssertTrue(text.contains("title: \"../quote\\\"\\n---\\nfolder: injected\""))
        XCTAssertEqual(text.components(separatedBy: "\n---\n").count, 2)
        XCTAssertTrue(text.contains("Original transcript")); XCTAssertTrue(text.contains("Source text"))
        XCTAssertTrue(text.contains(note.segments[0].id.uuidString))
        let invalid = try source("broken.txt", data: Data([0xff, 0xfe]))
        XCTAssertThrowsError(try store.importText(from: invalid))
        XCTAssertEqual(store.notes.count, 1)
    }

    func testRecallIsExtractiveLinkedAndTrashExcluded() throws {
        var note = try store.createNote(title: "Planning", body: "Edited summary")
        let segment = TranscriptSegment(start: 6, end: 9, text: "Do not order the red bicycle for Alex.")
        note.segments = [segment]; try store.save(note)
        let result = store.recall(query: "red bicycle")
        XCTAssertTrue(result.hasAnswer); XCTAssertEqual(result.excerpts.first?.text, segment.text)
        XCTAssertEqual(result.excerpts.first?.noteID, note.id); XCTAssertEqual(result.excerpts.first?.segmentID, segment.id)
        XCTAssertEqual(result.excerpts.first?.start, 6)
        XCTAssertFalse(store.recall(query: "invisible spaceship").hasAnswer)
        XCTAssertFalse(store.recall(query: "what is the").hasAnswer)
        XCTAssertTrue(store.highlights(for: note).allSatisfy { $0.label.hasPrefix("Extractive highlight") })
        try store.trash(id: note.id)
        XCTAssertFalse(store.recall(query: "bicycle").hasAnswer)
        XCTAssertTrue(store.filteredNotes().isEmpty); XCTAssertEqual(store.filteredNotes(trash: true).count, 1)
        try store.restore(id: note.id); XCTAssertTrue(store.recall(query: "bicycle").hasAnswer)
    }

    func testRetentionOffByDefaultExplicitApplyIsRecoverable() throws {
        let note = try store.createNote(body: "Keep this")
        let cutoff = Date().addingTimeInterval(60)
        XCTAssertTrue(store.retentionPreview(olderThan: cutoff).isEmpty)
        XCTAssertEqual(store.retentionPreview(olderThan: cutoff, enabled: true).map(\.id), [note.id])
        XCTAssertNil(store.note(id: note.id)?.trashedAt)
        XCTAssertThrowsError(try store.purge(id: note.id))
        try store.applyRetention(noteIDs: [note.id]); XCTAssertNotNil(store.note(id: note.id)?.trashedAt)
        try store.restore(id: note.id); XCTAssertNil(store.note(id: note.id)?.trashedAt)
    }

    func testPurgeRollsBackAudioWhenIndexCommitFails() throws {
        let original = try source("recording.wav")
        let note = try store.importAudio(from: original); try store.trash(id: note.id)
        let retained = try XCTUnwrap(store.audioURL(for: note))
        let backup = root.appendingPathComponent("old-index.json")
        try FileManager.default.moveItem(at: store.indexURL, to: backup)
        try FileManager.default.createDirectory(at: store.indexURL, withIntermediateDirectories: false)
        XCTAssertThrowsError(try store.purge(id: note.id))
        XCTAssertNotNil(store.note(id: note.id)); XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        try FileManager.default.removeItem(at: store.indexURL); try FileManager.default.moveItem(at: backup, to: store.indexURL)
        try store.purge(id: note.id)
        XCTAssertNil(store.note(id: note.id)); XCTAssertFalse(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertThrowsError(try store.save(note))
    }

    func testInterruptedPurgeRestoresReferencedAudioOnRestart() throws {
        let original = try source("interrupted.wav")
        let note = try store.importAudio(from: original); try store.trash(id: note.id)
        let retained = try XCTUnwrap(store.audioURL(for: note))
        let staged = store.directory.appendingPathComponent("pending-purge").appendingPathComponent(retained.lastPathComponent)
        try FileManager.default.moveItem(at: retained, to: staged)
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        XCTAssertEqual(reopened.notes.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.audioURL(for: reopened.notes[0]))), try Data(contentsOf: original))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        try reopened.purge(id: note.id)
        // Simulate crash after committed index, before staged-file cleanup.
        try Data(contentsOf: original).write(to: staged)
        let final = CaptureStore(directory: store.directory); try final.load()
        XCTAssertTrue(final.notes.isEmpty); XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testDraftRecoveryPreservesOriginalUntilExplicitDiscard() throws {
        let draftURL = store.recordingDraftDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        let bytes = Data([0, 10, 250, 9]); try bytes.write(to: draftURL)
        let restarted = CaptureStore(directory: store.directory); try restarted.load()
        let draft = try XCTUnwrap(restarted.drafts().first)
        let note = try restarted.recoverDraft(draft)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restarted.audioURL(for: note))), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
        try restarted.discardDraft(draft); XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
    }

    func testInvalidSegmentsAndSymlinkSourcesCannotChangeLibrary() throws {
        var note = try store.createNote(body: "Keep")
        note.segments = [TranscriptSegment(start: 5, end: 2, text: "Invalid")]
        XCTAssertThrowsError(try store.save(note)); XCTAssertTrue(store.notes[0].segments.isEmpty)
        let original = try source("real.wav")
        let link = root.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try store.importAudio(from: link)); XCTAssertEqual(store.notes.count, 1)
        let audioRoot = store.audioDirectory
        try FileManager.default.removeItem(at: audioRoot)
        try FileManager.default.createSymbolicLink(at: audioRoot, withDestinationURL: root)
        XCTAssertThrowsError(try store.createNote(body: "Do not write through link"))
        XCTAssertEqual(store.notes.count, 1)
    }

    func testExternalIndexChangeIsNeverSilentlyOverwritten() throws {
        let note = try store.createNote(body: "One")
        let other = CaptureStore(directory: store.directory); try other.load()
        _ = try other.createNote(body: "Two")
        let committedBytes = try Data(contentsOf: store.indexURL)
        var stale = note; stale.body = "Stale change"
        XCTAssertThrowsError(try store.save(stale))
        XCTAssertEqual(try Data(contentsOf: store.indexURL), committedBytes)
        XCTAssertEqual(store.notes.count, 1)
        try store.load(); XCTAssertEqual(store.notes.count, 2)
    }

    func testRepeatedSourceParagraphsHaveDistinctLinks() throws {
        _ = try store.createNote(body: "Repeat this source\nRepeat this source")
        let excerpts = store.recall(query: "Repeat").excerpts
        XCTAssertEqual(excerpts.count, 2)
        XCTAssertEqual(Set(excerpts.map(\.id)).count, 2)
    }

    func testConcurrentWritersHoldAdvisoryLockAndRejectStaleUpdate() throws {
        let original = try store.createNote(body: "Original")
        let firstStore = CaptureStore(directory: store.directory); try firstStore.load()
        let secondStore = CaptureStore(directory: store.directory); try secondStore.load()
        var first = original; first.body = "First writer committed"
        var second = original; second.body = "Second writer committed"
        let firstJob = WriteJob(store: firstStore, note: first)
        let secondJob = WriteJob(store: secondStore, note: second)
        let baselineData = try Data(contentsOf: store.indexURL)
        let lockPath = store.directory.appendingPathComponent(".library.lock").path
        let descriptor = Darwin.open(lockPath, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { _ = captureTestFlock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        XCTAssertEqual(captureTestFlock(descriptor, LOCK_EX), 0)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchGroup()
        for job in [firstJob, secondJob] {
            finished.enter()
            DispatchQueue.global().async {
                started.signal()
                job.run()
                finished.leave()
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        // A raw atomic write without flock would finish while this external lock is held.
        XCTAssertEqual(finished.wait(timeout: .now() + 0.15), .timedOut)
        XCTAssertEqual(try Data(contentsOf: store.indexURL), baselineData)
        XCTAssertEqual(captureTestFlock(descriptor, LOCK_UN), 0)
        XCTAssertEqual(finished.wait(timeout: .now() + 5), .success)
        let outcomes = [try XCTUnwrap(firstJob.result), try XCTUnwrap(secondJob.result)]
        let successes = outcomes.compactMap { try? $0.get() }
        let failures = outcomes.compactMap { outcome -> Error? in if case .failure(let error) = outcome { return error }; return nil }
        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures.first?.localizedDescription.contains("changed on disk") == true)
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        XCTAssertEqual(reopened.notes.count, 1)
        XCTAssertEqual(reopened.notes.first?.body, successes.first)
        let failedJob = firstJob.succeeded ? secondJob : firstJob
        XCTAssertEqual(failedJob.store.note(id: original.id)?.body, "Original")
    }

    func testEditedTranscriptSurvivesRestartWithoutReplacingOriginalSource() throws {
        var note = try store.createNote(title: "Correctable source")
        let original = TranscriptSegment(start: 1, end: 3, text: "Order fifteen blue notebooks.")
        note.segments = [original]; note.originalTranscript = original.text
        try store.save(note)
        var correction = try XCTUnwrap(store.note(id: note.id))
        let edited = TranscriptSegment(id: original.id, start: 1.2, end: 3.5, text: "Order fifty blue notebooks.")
        correction.editedSegments = [edited]
        try store.save(correction)
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        let restored = try XCTUnwrap(reopened.note(id: note.id))
        XCTAssertEqual(restored.editedSegments, [edited])
        XCTAssertEqual(restored.segments, [original])
        XCTAssertEqual(restored.originalTranscript, original.text)
        XCTAssertEqual(reopened.filteredNotes(query: "fifty").map(\.id), [note.id])
        let excerpt = try XCTUnwrap(reopened.recall(query: "fifty").excerpts.first)
        XCTAssertEqual(excerpt.segmentID, original.id); XCTAssertEqual(excerpt.start, 1.2)
        XCTAssertTrue(excerpt.label.contains("user correction"))
        let sharedPhrase = reopened.recall(query: "blue notebooks").excerpts
        XCTAssertEqual(sharedPhrase.count, 2)
        XCTAssertEqual(Set(sharedPhrase.map(\.id)).count, 2)
        let exported = try reopened.exportMarkdown(noteID: note.id, to: root)
        let text = try String(contentsOf: exported, encoding: .utf8)
        XCTAssertTrue(text.contains("Edited transcript segments"))
        XCTAssertTrue(text.contains(original.text)); XCTAssertTrue(text.contains(edited.text))
    }

    func testLegacyIndexWithoutEditedSegmentsRemainsReadable() throws {
        var note = try store.createNote(body: "Legacy note")
        note.segments = [TranscriptSegment(start: 0, end: 2, text: "Legacy source")]
        note.originalTranscript = "Legacy source"; try store.save(note)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.indexURL)) as? [String: Any])
        var rows = try XCTUnwrap(object["notes"] as? [[String: Any]])
        rows[0].removeValue(forKey: "editedSegments"); object["notes"] = rows
        try JSONSerialization.data(withJSONObject: object).write(to: store.indexURL)
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        let restored = try XCTUnwrap(reopened.note(id: note.id))
        XCTAssertNil(restored.editedSegments)
        XCTAssertEqual(restored.segments, note.segments)
        XCTAssertEqual(restored.originalTranscript, note.originalTranscript)
        XCTAssertEqual(restored.body, note.body)
    }

    func testInvalidEditedTimingsAndDuplicateIDsDoNotAlterSavedSources() throws {
        var note = try store.createNote(body: "Keep the original")
        let original = TranscriptSegment(start: 0, end: 4, text: "Original immutable source")
        note.segments = [original]; note.originalTranscript = original.text; try store.save(note)
        for invalid in [
            [TranscriptSegment(start: 4, end: 1, text: "Reversed")],
            [TranscriptSegment(start: .infinity, end: .infinity, text: "Nonfinite")],
            [original, original]
        ] {
            var changed = note; changed.editedSegments = invalid
            XCTAssertThrowsError(try store.save(changed))
            XCTAssertNil(store.note(id: note.id)?.editedSegments)
            XCTAssertEqual(store.note(id: note.id)?.segments, [original])
        }
        let reopened = CaptureStore(directory: store.directory); try reopened.load()
        XCTAssertNil(reopened.notes.first?.editedSegments)
        XCTAssertEqual(reopened.notes.first?.originalTranscript, original.text)
    }

    func testAppOwnedFilesArePrivateWithoutChangingImportOriginalPermissions() throws {
        let original = try source("public-source.wav")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: original.path)
        let note = try store.importAudio(from: original)
        let audio = try XCTUnwrap(store.audioURL(for: note))
        func mode(_ url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
        }
        XCTAssertEqual(try mode(original), 0o644)
        for folder in [store.directory, store.audioDirectory, store.recordingDraftDirectory, store.directory.appendingPathComponent("pending-purge")] {
            XCTAssertEqual(try mode(folder), 0o700)
        }
        XCTAssertEqual(try mode(store.indexURL), 0o600)
        XCTAssertEqual(try mode(audio), 0o600)
        XCTAssertEqual(try mode(store.directory.appendingPathComponent(".library.lock")), 0o600)
        var updated = note; updated.title = "Private replacement index"; try store.save(updated)
        XCTAssertEqual(try mode(store.indexURL), 0o600)
        XCTAssertEqual(try mode(original), 0o644)
    }

    /// Each job exclusively owns one store after creation; only its result crosses queues.
    private final class WriteJob: @unchecked Sendable {
        let store: CaptureStore
        let note: CaptureNote
        private let gate = NSLock()
        private var storedResult: Result<String, Error>?
        init(store: CaptureStore, note: CaptureNote) { self.store = store; self.note = note }
        var result: Result<String, Error>? { gate.lock(); defer { gate.unlock() }; return storedResult }
        var succeeded: Bool { if case .success? = result { return true }; return false }
        func run() {
            let outcome: Result<String, Error>
            do { try store.save(note); outcome = .success(note.body) }
            catch { outcome = .failure(error) }
            gate.lock(); storedResult = outcome; gate.unlock()
        }
    }
}
