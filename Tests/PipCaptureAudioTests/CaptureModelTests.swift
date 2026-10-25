import CaptureCore
import Foundation
import XCTest
@testable import PipCapture

private final class FailOnceRemovingFileManager: FileManager {
    private var failedURL: URL?

    func failOnceRemoving(_ url: URL) { failedURL = url.standardizedFileURL }

    override func removeItem(at URL: URL) throws {
        if failedURL == URL.standardizedFileURL {
            failedURL = nil
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: URL)
    }
}

/// Independent round-one regressions. These use the real editor/store path with
/// synthetic data and never request microphone access or launch a recogniser.
final class CaptureModelTests: XCTestCase {
    @MainActor
    private func withModel(fileManager: FileManager = .default, _ work: (CaptureModel, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-model-audit-" + UUID().uuidString)
        let model = CaptureModel(directory: root, fileManager: fileManager)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(model.loadFailure)
        try work(model, root)
    }

    @MainActor
    func testPendingEditorSavePreservesCompletedTranscriptionProvenance() throws {
        try withModel { model, root in
            let source = root.appendingPathComponent("synthetic.wav")
            let bytes = Data([1, 2, 3, 4])
            try bytes.write(to: source)
            let original = try model.store.importAudio(from: source)
            model.refresh()
            var pending = original
            pending.body = "My correction: do not spend £900."
            pending.tags = ["Reviewed"]
            model.edit(pending)

            // Reproduce an async completion after the editor snapshot was made.
            var completed = original
            completed.body = "Do not spend nine hundred."
            completed.originalTranscript = "Do not spend nine hundred."
            let segment = TranscriptSegment(start: 0, end: 3, text: completed.body)
            completed.segments = [segment]
            completed.transcriptionEngine = "Synthetic completed recogniser"
            completed.duration = 3
            try model.store.save(completed)
            model.refresh()

            XCTAssertTrue(model.saveAll())
            let saved = try XCTUnwrap(model.store.note(id: original.id))
            XCTAssertEqual(saved.body, pending.body)
            XCTAssertEqual(saved.tags, pending.tags)
            XCTAssertEqual(saved.originalTranscript, completed.originalTranscript)
            XCTAssertEqual(saved.segments, [segment])
            XCTAssertEqual(saved.transcriptionEngine, completed.transcriptionEngine)
            XCTAssertEqual(saved.duration, 3)
            XCTAssertEqual(saved.audioFilename, original.audioFilename)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.store.audioURL(for: saved))), bytes)
            let reopened = CaptureStore(directory: model.store.directory)
            try reopened.load()
            XCTAssertEqual(reopened.note(id: saved.id)?.segments, [segment])
        }
    }

    @MainActor
    func testSaveSelectedPersistsCurrentPendingEditorValues() throws {
        try withModel { model, _ in
            model.createText()
            let initial = try XCTUnwrap(model.selected)
            var pending = initial
            pending.title = "Synthetic current editor title"
            pending.body = "Synthetic current editor body"
            pending.favourite = true
            model.edit(pending)

            XCTAssertEqual(model.selected?.title, pending.title)
            XCTAssertTrue(model.saveSelected())

            let saved = try XCTUnwrap(model.store.note(id: initial.id))
            XCTAssertEqual(saved.title, pending.title)
            XCTAssertEqual(saved.body, pending.body)
            XCTAssertTrue(saved.favourite)
            XCTAssertNil(model.edits[initial.id])

            let reopened = CaptureStore(directory: model.store.directory)
            try reopened.load()
            XCTAssertEqual(reopened.note(id: initial.id)?.title, pending.title)
            XCTAssertEqual(reopened.note(id: initial.id)?.body, pending.body)
            XCTAssertTrue(reopened.note(id: initial.id)?.favourite == true)
        }
    }

    @MainActor
    func testRetentionSavesPendingEditsAndQuitCannotResurrectCapture() throws {
        try withModel { model, _ in
            let original = try model.store.createNote(body: "Old saved text")
            model.refresh()
            var pending = original
            pending.body = "Important pending correction"
            model.edit(pending)

            model.applyRetention([original.id])
            XCTAssertEqual(model.store.note(id: original.id)?.body, pending.body)
            XCTAssertNotNil(model.store.note(id: original.id)?.trashedAt)
            XCTAssertNil(model.edits[original.id])
            XCTAssertTrue(model.saveAll()) // same operation used by quit
            XCTAssertNotNil(model.store.note(id: original.id)?.trashedAt)
            let reopened = CaptureStore(directory: model.store.directory)
            try reopened.load()
            XCTAssertNotNil(reopened.note(id: original.id)?.trashedAt)
            XCTAssertEqual(reopened.note(id: original.id)?.body, pending.body)
        }
    }

    @MainActor
    func testStaleEditorCannotUndoAuthoritativeTrashState() throws {
        try withModel { model, _ in
            var stale = try model.store.createNote(body: "Saved before trash")
            stale.body = "Later correction"
            model.edit(stale)
            try model.store.applyRetention(noteIDs: [stale.id])
            model.refresh()
            XCTAssertTrue(model.saveAll())
            XCTAssertNotNil(model.store.note(id: stale.id)?.trashedAt)
            XCTAssertEqual(model.store.note(id: stale.id)?.body, stale.body)
        }
    }

    @MainActor
    func testRetentionDoesNotProceedWhenPendingEditSaveConflicts() throws {
        try withModel { model, _ in
            var pending = try model.store.createNote(body: "Original")
            pending.body = "Unsaved editor content"
            model.edit(pending)
            let other = CaptureStore(directory: model.store.directory)
            try other.load()
            _ = try other.createNote(body: "External change must survive")
            let diskBefore = try Data(contentsOf: model.store.indexURL)

            model.applyRetention([pending.id])
            XCTAssertNil(model.store.note(id: pending.id)?.trashedAt)
            XCTAssertEqual(model.edits[pending.id]?.body, pending.body)
            XCTAssertEqual(try Data(contentsOf: model.store.indexURL), diskBefore)
        }
    }

    @MainActor
    func testRecoveryReportsCommittedNoteWhenDraftCleanupIsPending() throws {
        let failingFileManager = FailOnceRemovingFileManager()
        try withModel(fileManager: failingFileManager) { model, _ in
            let draftURL = model.store.recordingDraftDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let bytes = Data([0, 7, 8, 255, 1]); try bytes.write(to: draftURL)
            let draft = try XCTUnwrap(model.store.drafts().first)
            failingFileManager.failOnceRemoving(draftURL)

            model.recoverDraft(draft)

            let committed = try XCTUnwrap(model.store.notes.first)
            XCTAssertEqual(model.store.notes.count, 1)
            XCTAssertEqual(model.selectedID, committed.id)
            XCTAssertTrue(model.message?.localizedCaseInsensitiveContains("recovered") == true)
            XCTAssertTrue(model.message?.localizedCaseInsensitiveContains("cleanup is pending") == true)
            XCTAssertTrue(model.recoveredDrafts.contains(where: { $0.url.standardizedFileURL == draftURL.standardizedFileURL }))
            XCTAssertTrue(FileManager.default.fileExists(atPath: draftURL.path))
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(model.store.audioURL(for: committed))), bytes)

            // The injected unlink failure is one-shot; retry resolves the same note and removes only the draft copy.
            model.recoverDraft(draft)
            XCTAssertEqual(model.store.notes.map(\.id), [committed.id])
            XCTAssertEqual(model.selectedID, committed.id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))
            XCTAssertFalse(model.recoveredDrafts.contains(where: { $0.url.standardizedFileURL == draftURL.standardizedFileURL }))
        }
    }
}
