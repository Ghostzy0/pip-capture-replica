import CaptureCore
import Darwin
import Foundation
import XCTest
@testable import PipCapture

/// Independent round-one regressions. These use the real editor/store path with
/// synthetic data and never request microphone access or launch a recogniser.
final class CaptureModelTests: XCTestCase {
    @MainActor
    private func withModel(_ work: (CaptureModel, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-model-audit-" + UUID().uuidString)
        let model = CaptureModel(directory: root)
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
}
