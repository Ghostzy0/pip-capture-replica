import CaptureCore
import Foundation
import XCTest
@testable import PipCapture

final class AppEditionTests: XCTestCase {
    func testEditionMetadataSeparatesInstallAndStorageIdentities() throws {
        XCTAssertEqual(Set(AppEdition.allCases.map(\.bundleID)).count, 4)
        XCTAssertEqual(Set(AppEdition.allCases.map(\.storageName)).count, 4)
        XCTAssertEqual(Set(AppEdition.allCases.map(\.name)).count, 4)
        for edition in AppEdition.allCases {
            XCTAssertEqual(try XCTUnwrap(AppEdition(rawValue: edition.rawValue)), edition)
            XCTAssertFalse(edition.storageName.contains("/"))
            XCTAssertFalse(edition.storageName.contains("\\"))
            XCTAssertEqual(edition.version, edition.hasExtras ? "0.2.0-alpha.4" : "0.1.0-alpha.4")
        }
        // Existing Pip Core libraries and native permission identity stay reachable.
        XCTAssertEqual(AppEdition.pipCore.bundleID, "com.pipreps.capture")
        XCTAssertEqual(AppEdition.pipCore.storageName, "Pip Capture")
        XCTAssertEqual(AppEdition.pipCore.name, "Pip Capture")
    }

    func testAppearanceAndExtrasAreIndependentAxes() {
        XCTAssertFalse(AppEdition.neutralCore.isPip); XCTAssertFalse(AppEdition.neutralCore.hasExtras)
        XCTAssertFalse(AppEdition.neutralPlus.isPip); XCTAssertTrue(AppEdition.neutralPlus.hasExtras)
        XCTAssertTrue(AppEdition.pipCore.isPip); XCTAssertFalse(AppEdition.pipCore.hasExtras)
        XCTAssertTrue(AppEdition.pipPlus.isPip); XCTAssertTrue(AppEdition.pipPlus.hasExtras)
    }

    func testInfoDictionaryIsAuthoritativeAndInvalidConfigurationFallsBackToCore() {
        for edition in AppEdition.allCases {
            XCTAssertEqual(AppEdition.edition(infoDictionary: [AppEdition.infoKey: edition.rawValue]), edition)
        }
        let invalid: [[String: Any]?] = [nil, [:], [AppEdition.infoKey: "unknown-plus"], [AppEdition.infoKey: true], ["PipCaptureExtras": true]]
        for metadata in invalid {
            let resolved = AppEdition.edition(infoDictionary: metadata)
            XCTAssertEqual(resolved, .pipCore)
            XCTAssertFalse(resolved.hasExtras)
        }
        XCTAssertNil(AppEdition(rawValue: "unknown"))
    }

    @MainActor
    func testPlusTagFilterComposesWithSearchFolderFavouritesAndTrash() throws {
        for edition in [AppEdition.neutralPlus, .pipPlus] {
            try withModel(edition) { model in
                var first = try model.store.createNote(title: "Work budget", body: "budget review", tags: ["alpha", "shared"], folder: "Work")
                first.favourite = true; try model.store.save(first)
                let second = try model.store.createNote(title: "Other budget", body: "budget review", tags: ["beta"], folder: "Work")
                _ = try model.store.createNote(title: "Home", tags: ["home"], folder: "Home")
                let deleted = try model.store.createNote(title: "Deleted budget", body: "budget review", tags: ["retired"], folder: "Work")
                try model.store.trash(id: deleted.id); model.refresh()
                let originalNotes = model.store.notes

                model.folder = "Work"; model.query = "budget"; model.selectedTag = "alpha"
                XCTAssertEqual(model.visibleNotes.map(\.id), [first.id])
                XCTAssertEqual(model.availableTags, ["alpha", "beta", "shared"])
                model.section = .favourites
                XCTAssertEqual(model.visibleNotes.map(\.id), [first.id])
                XCTAssertEqual(model.availableTags, ["alpha", "shared"])
                model.query = "no-match"
                XCTAssertTrue(model.visibleNotes.isEmpty)
                XCTAssertEqual(model.availableTags, ["alpha", "shared"])

                model.section = .inbox; model.query = "budget"; model.selectedTag = ""
                XCTAssertEqual(Set(model.visibleNotes.map(\.id)), Set([first.id, second.id]))
                model.section = .trash; model.selectedTag = "retired"
                XCTAssertEqual(model.availableTags, ["retired"])
                XCTAssertEqual(model.visibleNotes.map(\.id), [deleted.id])
                model.selectedTag = "alpha"; XCTAssertTrue(model.visibleNotes.isEmpty)
                model.section = .inbox; model.folder = "Home"; model.query = ""; model.selectedTag = ""
                XCTAssertEqual(model.availableTags, ["home"])
                XCTAssertFalse(model.visibleNotes.contains { $0.id == deleted.id })
                XCTAssertEqual(model.store.notes, originalNotes, "Filtering must never rewrite captures or tags")
            }
        }
    }

    @MainActor
    func testCoreEditionsIgnorePersistedOrProgrammaticallySelectedTag() throws {
        for edition in [AppEdition.neutralCore, .pipCore] {
            try withModel(edition) { model in
                let first = try model.store.createNote(title: "One", tags: ["one"], folder: "Work")
                let second = try model.store.createNote(title: "Two", tags: ["two"], folder: "Work")
                model.refresh(); model.folder = "Work"; model.selectedTag = "one"
                XCTAssertTrue(model.availableTags.isEmpty)
                XCTAssertEqual(Set(model.visibleNotes.map(\.id)), Set([first.id, second.id]))
                model.query = "Two"
                XCTAssertEqual(model.visibleNotes.map(\.id), [second.id])
            }
        }
    }

    @MainActor
    func testTagChoicesRefreshAfterEditsWithoutChangingOtherCaptures() throws {
        try withModel(.pipPlus) { model in
            var note = try model.store.createNote(title: "Edit tags", tags: ["old"], folder: "Work")
            let untouched = try model.store.createNote(title: "Other", tags: ["stable"], folder: "Work")
            model.refresh(); model.folder = "Work"
            XCTAssertEqual(model.availableTags, ["old", "stable"])
            note.tags = ["new"]; XCTAssertTrue(model.save(note))
            XCTAssertEqual(model.availableTags, ["new", "stable"])
            model.selectedTag = "new"; XCTAssertEqual(model.visibleNotes.map(\.id), [note.id])
            note.tags = []; XCTAssertTrue(model.save(note))
            XCTAssertEqual(model.availableTags, ["stable"])
            XCTAssertTrue(model.visibleNotes.isEmpty)
            model.selectedTag = ""; XCTAssertEqual(model.visibleNotes.count, 2)
            XCTAssertEqual(model.store.note(id: untouched.id), untouched)
        }
    }

    @MainActor
    func testExplicitCreateAndDraftRecoveryClearTagAndRevealSelectedCapture() throws {
        try withModel(.pipPlus) { model in
            _ = try model.store.createNote(title: "Old", tags: ["old"], folder: "Work")
            model.refresh(); model.folder = "Work"; model.query = "Old"; model.selectedTag = "old"
            model.createText()
            XCTAssertEqual(model.selectedTag, "")
            XCTAssertTrue(model.visibleNotes.contains { $0.id == model.selectedID })
            model.selectedTag = "missing"; model.section = .trash; model.folder = "Other"; model.query = "No match"
            let draftURL = model.store.recordingDraftDirectory.appendingPathComponent(UUID().uuidString + ".wav")
            try Data([0, 1, 255]).write(to: draftURL)
            let draft = try XCTUnwrap(model.store.drafts().first)
            model.recoverDraft(draft)
            XCTAssertEqual(model.selectedTag, "")
            XCTAssertEqual(model.section, .inbox)
            XCTAssertTrue(model.folder.isEmpty); XCTAssertTrue(model.query.isEmpty)
            XCTAssertTrue(model.visibleNotes.contains { $0.id == model.selectedID })
        }
    }

    @MainActor
    private func withModel(_ edition: AppEdition, _ work: (CaptureModel) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-edition-tests-" + UUID().uuidString)
        let model = CaptureModel(directory: root, edition: edition)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(model.loadFailure)
        try work(model)
    }
}
