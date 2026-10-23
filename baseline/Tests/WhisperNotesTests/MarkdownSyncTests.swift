import XCTest
@testable import WhisperNotesLib

final class MarkdownSyncTests: XCTestCase {
    var sync: MarkdownSync!
    var tempDir: URL!
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("whisper-test-\(UUID().uuidString)")
        sync = MarkdownSync(baseURL: tempDir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tempDir); super.tearDown() }
    private func url(_ note: Transcription, folder: String? = nil) -> URL {
        (folder.map { tempDir.appendingPathComponent($0) } ?? tempDir).appendingPathComponent(sync.filename(for: note))
    }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testWriteCreatesMarkdownFile() throws {
        let note = makeTranscription(title: "My Note", content: "Hello world")
        XCTAssertTrue(sync.write(note, folderName: nil))
        let content = try text(url(note))
        XCTAssertTrue(content.contains("# My Note")); XCTAssertTrue(content.contains("Hello world"))
        XCTAssertTrue(content.contains("id: \(note.id.uuidString)"))
    }
    func testWriteIntoFolder() {
        let note = makeTranscription(title: "FolderNote", content: "In folder")
        XCTAssertTrue(sync.write(note, folderName: "MyFolder")); XCTAssertTrue(exists(url(note, folder: "MyFolder")))
    }
    func testWriteWithTags() throws {
        let note = makeTranscription(tags: [Tag(id: UUID(), name: "Important", color: "#FF453A")])
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertTrue(try text(url(note)).contains("tags: [\"Important\"]"))
    }
    func testWriteWithFavorite() throws {
        let note = makeTranscription(isFavorite: true)
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertTrue(try text(url(note)).contains("favorite: true"))
    }
    func testWriteWithDuration() throws {
        let note = makeTranscription(duration: 120)
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertTrue(try text(url(note)).contains("duration: 120"))
    }
    func testWriteRenamesOnTitleChange() {
        var note = makeTranscription(title: "OldTitle")
        XCTAssertTrue(sync.write(note, folderName: nil)); let oldURL = url(note)
        // A rename retains identity. A different UUID is a different capture and must survive.
        note.title = "NewTitle"
        XCTAssertTrue(sync.write(note, folderName: nil, previousTitle: "OldTitle"))
        XCTAssertFalse(exists(oldURL)); XCTAssertTrue(exists(url(note)))
    }
    func testWriteMovesOnFolderChange() {
        let note = makeTranscription(title: "Note")
        XCTAssertTrue(sync.write(note, folderName: "OldFolder"))
        XCTAssertTrue(sync.write(note, folderName: "NewFolder", previousFolderName: "OldFolder"))
        XCTAssertFalse(exists(url(note, folder: "OldFolder"))); XCTAssertTrue(exists(url(note, folder: "NewFolder")))
    }
    func testDeleteRemovesFile() {
        let note = makeTranscription(title: "ToDelete")
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertTrue(sync.delete(note, folderName: nil))
        XCTAssertFalse(exists(url(note)))
    }
    func testCreateFolderDir() {
        XCTAssertTrue(sync.createFolderDir("Work")); var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Work").path, isDirectory: &isDir)); XCTAssertTrue(isDir.boolValue)
    }
    func testRenameFolderDir() {
        XCTAssertTrue(sync.createFolderDir("Old")); XCTAssertTrue(sync.renameFolderDir(from: "Old", to: "New"))
        XCTAssertFalse(exists(tempDir.appendingPathComponent("Old"))); XCTAssertTrue(exists(tempDir.appendingPathComponent("New")))
    }
    func testDeleteFolderDirMovesFilesToBase() {
        let note = makeTranscription(title: "MovedNote")
        XCTAssertTrue(sync.write(note, folderName: "ToDelete")); XCTAssertTrue(sync.deleteFolderDir("ToDelete"))
        XCTAssertFalse(exists(tempDir.appendingPathComponent("ToDelete"))); XCTAssertTrue(exists(url(note)))
    }
    func testSanitizeStripsInvalidCharacters() {
        let note = makeTranscription(title: "Test/Note:With\\Slashes")
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertTrue(sync.filename(for: note).hasPrefix("TestNoteWithSlashes--")); XCTAssertTrue(exists(url(note)))
    }
    func testSanitizeEmptyTitleBecomesUntitled() {
        let note = makeTranscription(title: "")
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertTrue(sync.filename(for: note).hasPrefix("untitled--")); XCTAssertTrue(exists(url(note)))
    }
    func testDotAndPathFolderOperationsCannotDeleteRootOrEscape() throws {
        let outside = tempDir.appendingPathComponent("outside.txt"); try "outside".write(to: outside, atomically: true, encoding: .utf8)
        let nested = MarkdownSync(baseURL: tempDir.appendingPathComponent("root"))
        let note = makeTranscription(content: "Keep root")
        XCTAssertTrue(nested.write(note, folderName: nil))
        for invalid in [".", "..", " ../ ", "../outside", "a/b", "a\\b", "a:b", "\n.\n"] {
            XCTAssertFalse(nested.createFolderDir(invalid))
            XCTAssertFalse(nested.deleteFolderDir(invalid))
            XCTAssertFalse(nested.renameFolderDir(from: invalid, to: "Safe"))
            XCTAssertFalse(nested.write(note, folderName: invalid))
        }
        XCTAssertEqual(try text(outside), "outside")
        XCTAssertTrue(exists(nested.baseURL.appendingPathComponent(nested.filename(for: note))))
    }
    func testSameAndSanitizedTitlesRetainSeparateNoteIdentities() throws {
        let notes = [makeTranscription(title: "Same", content: "One"), makeTranscription(title: "Same", content: "Two"), makeTranscription(title: "a/b", content: "Three"), makeTranscription(title: "ab", content: "Four")]
        for note in notes { XCTAssertTrue(sync.write(note, folderName: nil)) }
        XCTAssertEqual(Set(notes.map { sync.filename(for: $0) }).count, 4)
        for note in notes { XCTAssertTrue(try text(url(note)).contains(note.content)) }
        XCTAssertTrue(sync.delete(notes[0], folderName: nil)); XCTAssertTrue(exists(url(notes[1])))
    }
    func testFolderDeletionCollisionPreservesEveryFile() throws {
        let note = makeTranscription(content: "Folder source")
        XCTAssertTrue(sync.write(note, folderName: "Folder"))
        let rootCollision = url(note); try "unrelated root source".write(to: rootCollision, atomically: true, encoding: .utf8)
        XCTAssertFalse(sync.deleteFolderDir("Folder"))
        XCTAssertEqual(try text(rootCollision), "unrelated root source")
        XCTAssertTrue(try text(url(note, folder: "Folder")).contains("Folder source"))
    }
    func testFolderDeletionPreservesUnrecognizedFilesAndNestedFolders() throws {
        let note = makeTranscription(content: "Known source")
        XCTAssertTrue(sync.write(note, folderName: "Folder"))
        let extra = tempDir.appendingPathComponent("Folder/extra.bin"); try Data([0, 1, 255]).write(to: extra)
        XCTAssertFalse(sync.deleteFolderDir("Folder")); XCTAssertTrue(exists(url(note, folder: "Folder"))); XCTAssertEqual(try Data(contentsOf: extra), Data([0, 1, 255]))
        try FileManager.default.removeItem(at: extra)
        let nested = tempDir.appendingPathComponent("Folder/nested"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        XCTAssertFalse(sync.deleteFolderDir("Folder")); XCTAssertTrue(exists(nested)); XCTAssertTrue(exists(url(note, folder: "Folder")))
    }
    func testRenameCollisionAndFailedReplacementKeepSources() throws {
        XCTAssertTrue(sync.createFolderDir("One")); XCTAssertTrue(sync.createFolderDir("Two"))
        XCTAssertFalse(sync.renameFolderDir(from: "One", to: "Two")); XCTAssertTrue(exists(tempDir.appendingPathComponent("One")))
        var note = makeTranscription(title: "Old", content: "Original")
        XCTAssertTrue(sync.write(note, folderName: nil)); let old = url(note)
        note.title = "New"; let collision = url(note)
        try "unrelated".write(to: collision, atomically: true, encoding: .utf8)
        XCTAssertFalse(sync.write(note, folderName: nil, previousTitle: "Old"))
        XCTAssertTrue(try text(old).contains("Original")); XCTAssertEqual(try text(collision), "unrelated")
    }
    func testChildSymlinkCannotWriteOrDeleteOutsideSource() throws {
        let outside = tempDir.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let safe = tempDir.appendingPathComponent("safe"); let scoped = MarkdownSync(baseURL: safe)
        let marker = outside.appendingPathComponent("marker.md"); try "preserve".write(to: marker, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: safe.appendingPathComponent("Link"), withDestinationURL: outside)
        XCTAssertFalse(scoped.write(makeTranscription(), folderName: "Link")); XCTAssertFalse(scoped.deleteFolderDir("Link"))
        XCTAssertFalse(scoped.renameFolderDir(from: "Link", to: "Other")); XCTAssertEqual(try text(marker), "preserve")
    }
    func testLegacyMigrationDeletesOnlyMatchingFrontmatterIdentity() throws {
        let note = makeTranscription(title: "Legacy", content: "New")
        let legacy = tempDir.appendingPathComponent("Legacy.md")
        try "---\nid: \(note.id.uuidString)\n---\nOld".write(to: legacy, atomically: true, encoding: .utf8)
        XCTAssertTrue(sync.write(note, folderName: nil)); XCTAssertFalse(exists(legacy)); XCTAssertTrue(exists(url(note)))
        try "unrelated legacy note".write(to: legacy, atomically: true, encoding: .utf8)
        XCTAssertTrue(sync.delete(note, folderName: nil)); XCTAssertEqual(try text(legacy), "unrelated legacy note")
    }

    private func makeTranscription(title: String = "Test", content: String = "", isFavorite: Bool = false, duration: TimeInterval = 0, tags: [Tag] = []) -> Transcription {
        Transcription(id: UUID(), title: title, content: content, folderId: nil, isFavorite: isFavorite, duration: duration, audioFilename: nil, createdAt: Date(), updatedAt: Date(), tags: tags)
    }
}
