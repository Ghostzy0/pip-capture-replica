import Foundation
import Darwin
import CryptoKit

// Swift's Darwin overlay also exposes `struct flock`, which hides the C function.
@_silgen_name("flock") private func captureFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

/// Synchronous durable storage. Confine each instance to one actor/serial executor.
/// All mutations persist a candidate before publishing it in memory.
public final class CaptureStore {
    private struct Index: Codable { let version: Int; var notes: [CaptureNote] }
    public let directory: URL
    public var recordingDraftDirectory: URL { directory.appendingPathComponent("drafts", isDirectory: true) }
    public var audioDirectory: URL { directory.appendingPathComponent("audio", isDirectory: true) }
    private var pendingPurgeDirectory: URL { directory.appendingPathComponent("pending-purge", isDirectory: true) }
    public var indexURL: URL { directory.appendingPathComponent("library.json") }
    public private(set) var notes: [CaptureNote] = []
    public private(set) var lastError: String?
    private var loaded = false
    private var persistedIndexData: Data?
    private let transactionGate = NSRecursiveLock()
    private var transactionDepth = 0
    private let fm: FileManager
    private static let audioExtensions: Set<String> = ["m4a", "wav", "mp3", "aiff", "aif", "caf", "flac", "aac", "ogg", "mp4"]

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory.standardizedFileURL
        self.fm = fileManager
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pip Capture", isDirectory: true)
    }

    public func load() throws {
        do { try withStorageLock { try loadLocked() } }
        catch { loaded = false; lastError = error.localizedDescription; throw error }
    }

    private func loadLocked() throws {
        do {
            try prepareDirectories()
            guard fm.fileExists(atPath: indexURL.path) else {
                // Never infer committed deletion from a missing index while a purge is staged.
                guard try fm.contentsOfDirectory(atPath: pendingPurgeDirectory.path).isEmpty else { throw CaptureError.corruptIndex("The index is missing while audio deletion is pending.") }
                notes = []; persistedIndexData = nil; loaded = true; lastError = nil; return
            }
            try requireRegularFile(indexURL)
            let data = try Data(contentsOf: indexURL)
            let index: Index
            do { index = try decoder().decode(Index.self, from: data) }
            catch { throw CaptureError.corruptIndex("The JSON is malformed or incompatible.") }
            guard index.version == 1 else { throw CaptureError.corruptIndex("Unsupported library version \(index.version).") }
            do { try validate(index.notes) }
            catch { throw CaptureError.corruptIndex(error.localizedDescription) }
            try recoverPendingPurges(referencedBy: index.notes)
            notes = index.notes; persistedIndexData = data; loaded = true; lastError = nil
        } catch { loaded = false; lastError = error.localizedDescription; throw error }
    }

    @discardableResult public func createNote(title: String = "Untitled capture", body: String = "",
                                             tags: [String] = [], folder: String = "Inbox") throws -> CaptureNote {
        var note = CaptureNote(title: title, body: body, tags: tags, folder: folder)
        normalize(&note)
        try commit(notes + [note]); return note
    }

    /// Save existing notes only, preventing stale editors from resurrecting purged notes.
    public func save(_ incoming: CaptureNote) throws {
        guard let index = notes.firstIndex(where: { $0.id == incoming.id }) else { throw CaptureError.noteNotFound }
        var note = incoming
        note.createdAt = notes[index].createdAt; note.updatedAt = Date()
        normalize(&note)
        var candidate = notes; candidate[index] = note
        try commit(candidate)
    }

    public func note(id: UUID) -> CaptureNote? { notes.first { $0.id == id } }

    public func filteredNotes(query: String = "", folder: String? = nil, tag: String? = nil,
                              favouritesOnly: Bool = false, trash: Bool = false) -> [CaptureNote] {
        let needle = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return notes.filter { note in
            let transcriptText = note.segments.map(\.text) + (note.editedSegments ?? []).map(\.text)
            let searchable = ([note.title, note.body, note.originalTranscript ?? "", note.folder] + note.tags + transcriptText).joined(separator: "\n")
            return (note.trashedAt != nil) == trash && (folder == nil || note.folder == folder) &&
            (tag == nil || note.tags.contains(tag!)) && (!favouritesOnly || note.favourite) &&
            (needle.isEmpty || folded(searchable).contains(needle))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func trash(id: UUID) throws { try mutate(id) { $0.trashedAt = Date() } }
    public func restore(id: UUID) throws { try mutate(id) { $0.trashedAt = nil } }

    /// Only already-trashed captures may be permanently removed.
    public func purge(id: UUID) throws {
        try withStorageLock { try purgeLocked(id: id) }
    }

    private func purgeLocked(id: UUID) throws {
        guard let note = note(id: id), note.trashedAt != nil else { throw CaptureError.invalid("Move the capture to Trash before permanently deleting it.") }
        guard loaded else { throw CaptureError.notLoaded }
        var staged: URL?
        var original: URL?
        if let filename = note.audioFilename {
            let url = try ownedAudioURL(filename)
            if fm.fileExists(atPath: url.path) {
                try prepareDirectories(); try requireRegularFile(url)
                let pending = pendingPurgeDirectory.appendingPathComponent(filename)
                do { try fm.moveItem(at: url, to: pending); staged = pending; original = url }
                catch { lastError = error.localizedDescription; throw CaptureError.storage("The audio could not be staged for deletion. Nothing was removed from the library.") }
            }
        }
        do { try commit(notes.filter { $0.id != id }) }
        catch {
            if let staged, let original {
                do { try fm.moveItem(at: staged, to: original) }
                catch { lastError = "The library save failed and audio restoration is pending. Restart Capture to recover the staged original."; throw CaptureError.storage(lastError!) }
            }
            throw error
        }
        if let staged {
            do { try fm.removeItem(at: staged) }
            catch { let issue = CaptureError.storage("The capture was purged; retained audio cleanup is pending and will be retried when the library opens."); lastError = issue.localizedDescription; throw issue }
        }
    }

    /// Retention is off unless explicitly enabled by the caller. Preview never mutates.
    public func retentionPreview(olderThan cutoff: Date, enabled: Bool = false) -> [CaptureNote] {
        guard enabled else { return [] }
        return notes.filter { $0.trashedAt == nil && $0.updatedAt < cutoff }.sorted { $0.updatedAt < $1.updatedAt }
    }

    /// Explicitly approved IDs go to recoverable Trash, never directly to permanent deletion.
    public func applyRetention(noteIDs: [UUID]) throws {
        let ids = Set(noteIDs)
        guard ids.isSubset(of: Set(notes.map(\.id))) else { throw CaptureError.noteNotFound }
        let now = Date()
        try commit(notes.map { old in var note = old; if ids.contains(note.id) && note.trashedAt == nil { note.trashedAt = now; note.updatedAt = now }; return note })
    }

    @discardableResult public func importText(from source: URL) throws -> CaptureNote {
        guard ["txt", "md"].contains(source.pathExtension.lowercased()) else { throw CaptureError.invalid("Choose a UTF-8 .txt or .md file.") }
        try requireRegularFile(source)
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard ((attributes[.size] as? NSNumber)?.int64Value ?? 0) <= 25 * 1024 * 1024 else { throw CaptureError.invalid("Text imports are limited to 25 MB.") }
        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8) else { throw CaptureError.invalid("This file is not UTF-8 text. Save a UTF-8 copy and import it again.") }
        return try createNote(title: source.deletingPathExtension().lastPathComponent, body: text)
    }

    @discardableResult public func importAudio(from source: URL, title: String? = nil, duration: Double = 0) throws -> CaptureNote {
        var note = CaptureNote(title: title ?? source.deletingPathExtension().lastPathComponent, duration: duration)
        normalize(&note)
        let target = try copyAudio(source)
        note.audioFilename = target.lastPathComponent
        do { try commit(notes + [note]); return note }
        catch { try rollbackImport(target, originalError: error) }
    }

    public func attachAudio(to id: UUID, from source: URL, duration: Double = 0) throws {
        guard var note = note(id: id) else { throw CaptureError.noteNotFound }
        guard note.audioFilename == nil else { throw CaptureError.invalid("This capture already has an original audio source. Import the new recording as a separate capture to preserve both sources.") }
        let target = try copyAudio(source)
        note.audioFilename = target.lastPathComponent; note.duration = duration
        do { try save(note) }
        catch { try rollbackImport(target, originalError: error) }
    }

    public func audioURL(for note: CaptureNote) throws -> URL? {
        guard let filename = note.audioFilename else { return nil }
        let url = try ownedAudioURL(filename); try requireRegularFile(url); return url
    }

    public func drafts() throws -> [RecordingDraft] {
        try prepareDirectories()
        return try fm.contentsOfDirectory(at: recordingDraftDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            .compactMap { url in
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, Self.audioExtensions.contains(url.pathExtension.lowercased()) else { return nil }
                return RecordingDraft(filename: url.lastPathComponent, url: url, modifiedAt: values.contentModificationDate ?? .distantPast, byteCount: Int64(values.fileSize ?? 0))
            }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    @discardableResult public func recoverDraft(_ draft: RecordingDraft, title: String = "Recovered recording",
                                                duration: Double = 0) throws -> CaptureNote {
        try withStorageLock {
            let current = try validatedDraft(draft)
            let fingerprint = try contentFingerprint(of: current.url)
            if let recovered = notes.first(where: {
                $0.recoveredDraftFilename == current.filename && $0.recoveredDraftFingerprint == fingerprint
            }) {
                try verifyRecoveredAudio(recovered, expectedFingerprint: fingerprint)
                return recovered
            }

            var note = CaptureNote(title: title, duration: duration)
            normalize(&note)
            let target = try copyAudio(current.url)
            do {
                guard try contentFingerprint(of: target) == fingerprint else {
                    throw CaptureError.storage("The recording changed while it was being recovered. The draft is preserved; try again.")
                }
                note.audioFilename = target.lastPathComponent
                note.recoveredDraftFingerprint = fingerprint
                note.recoveredDraftFilename = current.filename
                try commit(notes + [note])
                return note
            } catch { try rollbackImport(target, originalError: error) }
        }
    }

    @discardableResult public func recoverDraft(at sourceURL: URL, title: String,
                                                duration: Double = 0) throws -> CaptureNote {
        guard let draft = try drafts().first(where: { $0.url.standardizedFileURL == sourceURL.standardizedFileURL }) else {
            throw CaptureError.invalid("This recording draft is no longer available.")
        }
        return try recoverDraft(draft, title: title, duration: duration)
    }

    public func discardDraft(_ draft: RecordingDraft) throws {
        try withStorageLock {
            let url = draft.url.standardizedFileURL
            guard url.deletingLastPathComponent() == recordingDraftDirectory.standardizedFileURL,
                  url.lastPathComponent == draft.filename,
                  Self.audioExtensions.contains(url.pathExtension.lowercased()) else {
                throw CaptureError.invalid("This recording draft is no longer available.")
            }
            // A retry after successful removal is complete. Never follow a changed file at the same path.
            guard fm.fileExists(atPath: url.path) else { return }
            try requireRegularFile(url)
            do { try fm.removeItem(at: url) } catch { lastError = error.localizedDescription; throw CaptureError.storage("The draft could not be removed.") }
        }
    }

    public func finishDraftRecovery(_ draft: RecordingDraft, for recoveredNote: CaptureNote) throws {
        try withStorageLock {
            let current = try validatedDraft(draft)
            guard let stored = notes.first(where: { $0.id == recoveredNote.id }),
                  stored.recoveredDraftFilename == current.filename,
                  let fingerprint = stored.recoveredDraftFingerprint,
                  fingerprint == recoveredNote.recoveredDraftFingerprint else {
                throw CaptureError.storage("The recovered note no longer matches this draft. The source is preserved.")
            }
            try verifyRecoveredAudio(stored, expectedFingerprint: fingerprint)
            guard try contentFingerprint(of: current.url) == fingerprint else {
                throw CaptureError.storage("The draft changed after recovery. The newer source is preserved for recovery.")
            }
            do { try fm.removeItem(at: current.url) }
            catch { lastError = error.localizedDescription; throw CaptureError.storage("The note is recovered, but its draft could not be removed.") }
        }
    }

    public func finishDraftRecovery(at sourceURL: URL, for recoveredNote: CaptureNote) throws {
        let standardizedURL = sourceURL.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent() == recordingDraftDirectory.standardizedFileURL else {
            throw CaptureError.invalid("This recording draft is no longer available.")
        }
        guard let draft = try drafts().first(where: { $0.url.standardizedFileURL == standardizedURL }) else {
            guard !fm.fileExists(atPath: standardizedURL.path) else {
                throw CaptureError.invalid("The retained recording draft could not be safely identified and was preserved.")
            }
            return
        }
        try finishDraftRecovery(draft, for: recoveredNote)
    }

    private func validatedDraft(_ draft: RecordingDraft) throws -> RecordingDraft {
        guard let current = try drafts().first(where: { $0.url.standardizedFileURL == draft.url.standardizedFileURL }),
              current.filename == draft.filename else { throw CaptureError.invalid("This recording draft is no longer available.") }
        return current
    }

    private func contentFingerprint(of url: URL) throws -> String {
        try requireRegularFile(url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func verifyRecoveredAudio(_ note: CaptureNote, expectedFingerprint: String) throws {
        guard let audioFilename = note.audioFilename else {
            throw CaptureError.storage("The recovered recording is missing its library audio. The draft is preserved for recovery.")
        }
        let recoveredAudio = try ownedAudioURL(audioFilename)
        guard fm.fileExists(atPath: recoveredAudio.path),
              try contentFingerprint(of: recoveredAudio) == expectedFingerprint else {
            throw CaptureError.storage("The recovered recording audio is missing or changed. The draft is preserved for recovery.")
        }
    }

    @discardableResult public func exportMarkdown(noteID: UUID, to destinationDirectory: URL) throws -> URL {
        guard let note = note(id: noteID) else { throw CaptureError.noteNotFound }
        do {
            let target = destinationDirectory.appendingPathComponent(exportStem(note) + ".md")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            func quoted<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
            let dates = ISO8601DateFormatter()
            var lines = ["---", "capture_id: \(try quoted(note.id.uuidString))", "title: \(try quoted(note.title))",
                         "tags: \(try quoted(note.tags))", "folder: \(try quoted(note.folder))",
                         "favourite: \(note.favourite)", "created_at: \(try quoted(dates.string(from: note.createdAt)))",
                         "updated_at: \(try quoted(dates.string(from: note.updatedAt)))", "duration_seconds: \(note.duration)"]
            if let audio = note.audioFilename { lines.append("audio_filename: \(try quoted(audio))") }
            if let engine = note.transcriptionEngine { lines.append("transcription_engine: \(try quoted(engine))") }
            if let trashed = note.trashedAt { lines.append("trashed_at: \(try quoted(dates.string(from: trashed)))") }
            lines += ["---", "", note.body]
            if let original = note.originalTranscript { lines += ["", "## Original transcript", "", original] }
            if !note.segments.isEmpty {
                lines += ["", "## Transcript source segments", ""]
                for segment in note.segments {
                    lines += ["### \(segment.start)–\(segment.end) seconds · \(segment.id.uuidString)", "", segment.text, ""]
                }
            }
            if let corrected = note.editedSegments {
                lines += ["", "## Edited transcript segments", "", "User corrections; original source segments are retained above.", ""]
                for segment in corrected {
                    lines += ["### \(segment.start)–\(segment.end) seconds · \(segment.id.uuidString)", "", segment.text, ""]
                }
            }
            try Data(lines.joined(separator: "\n").utf8).write(to: target, options: .withoutOverwriting)
            lastError = nil; return target
        } catch { lastError = error.localizedDescription; throw error }
    }

    @discardableResult public func exportAudio(noteID: UUID, to destinationDirectory: URL) throws -> URL {
        guard let note = note(id: noteID) else { throw CaptureError.noteNotFound }
        do {
            guard let source = try audioURL(for: note) else { throw CaptureError.invalid("This capture has no retained audio.") }
            let target = destinationDirectory.appendingPathComponent(exportStem(note) + "." + source.pathExtension)
            try fm.copyItem(at: source, to: target)
            lastError = nil; return target
        } catch { lastError = error.localizedDescription; throw error }
    }

    private func exportStem(_ note: CaptureNote) -> String {
        let safe = note.title.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" ? String(scalar) : "-"
        }.joined()
        // Bound UTF-8 bytes, including long combining sequences, below filesystem component limits.
        var bounded = ""
        for scalar in safe.unicodeScalars {
            guard bounded.utf8.count + String(scalar).utf8.count <= 160 else { break }
            bounded.unicodeScalars.append(scalar)
        }
        let title = bounded.trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
        return (title.isEmpty ? "capture" : title) + "-" + note.id.uuidString
    }

    private func mutate(_ id: UUID, _ block: (inout CaptureNote) -> Void) throws {
        guard var note = note(id: id) else { throw CaptureError.noteNotFound }; block(&note); try save(note)
    }

    private func normalize(_ note: inout CaptureNote) {
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { note.title = "Untitled capture" }
        if note.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { note.folder = "Inbox" }
        var seen = Set<String>()
        note.tags = note.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert(folded($0)).inserted }
    }

    private func commit(_ candidate: [CaptureNote]) throws {
        try withStorageLock { try commitLocked(candidate) }
    }

    private func commitLocked(_ candidate: [CaptureNote]) throws {
        guard loaded else { throw CaptureError.notLoaded }
        do {
            try validate(candidate); try prepareDirectories()
            if fm.fileExists(atPath: indexURL.path) {
                try requireRegularFile(indexURL)
                guard try Data(contentsOf: indexURL) == persistedIndexData else { throw CaptureError.storage("The library changed on disk. Reopen it before saving so the existing data is not overwritten.") }
            } else if persistedIndexData != nil { throw CaptureError.storage("The library index is missing. Restore it or reopen the library before saving.") }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .millisecondsSince1970
            let data = try encoder.encode(Index(version: 1, notes: candidate))
            try writeIndexAtomically(data)
            notes = candidate; persistedIndexData = data; lastError = nil
        } catch { lastError = error.localizedDescription; throw error }
    }

    private func decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970; return decoder }

    /// Create the replacement privately before atomically installing it in the same directory.
    private func writeIndexAtomically(_ data: Data) throws {
        let temporary = directory.appendingPathComponent(".library-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw CaptureError.storage("A private temporary index could not be created.") }
        var installed = false
        defer {
            Darwin.close(descriptor)
            if !installed { try? fm.removeItem(at: temporary) }
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let amount = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if amount < 0 {
                    if errno == EINTR { continue }
                    throw CaptureError.storage("The private temporary index could not be written.")
                }
                guard amount > 0 else { throw CaptureError.storage("The temporary index write did not finish.") }
                offset += amount
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw CaptureError.storage("The temporary index could not be flushed to storage.") }
        guard Darwin.rename(temporary.path, indexURL.path) == 0 else { throw CaptureError.storage("The library index could not be replaced atomically.") }
        installed = true
    }

    /// Hold the same advisory lock across reading/recovery, compare-and-write, and purge staging.
    /// Each outer call opens its own descriptor, so different stores/processes contend on the
    /// same stable lock inode. Nested commit inside purge reuses the already-held transaction.
    private func withStorageLock<T>(_ operation: () throws -> T) throws -> T {
        transactionGate.lock()
        defer { transactionGate.unlock() }
        if transactionDepth > 0 { return try operation() }
        do {
            try prepareDirectories()
            let lockURL = directory.appendingPathComponent(".library.lock")
            let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
            guard descriptor >= 0 else { throw CaptureError.storage("The library lock could not be opened. Check the app storage folder permissions.") }
            defer { Darwin.close(descriptor) }
            var info = stat()
            guard Darwin.fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw CaptureError.storage("The library lock is not a regular file. Preserve the existing storage folder and check its lock file.")
            }
            while captureFlock(descriptor, LOCK_EX) != 0 {
                guard errno == EINTR else { throw CaptureError.storage("The library lock could not be acquired. Try reopening the library.") }
            }
            transactionDepth = 1
            defer {
                transactionDepth = 0
                _ = captureFlock(descriptor, LOCK_UN)
            }
            return try operation()
        } catch { lastError = error.localizedDescription; throw error }
    }

    private func validate(_ notes: [CaptureNote]) throws {
        guard Set(notes.map(\.id)).count == notes.count else { throw CaptureError.invalid("The library contains duplicate capture IDs.") }
        var audioNames = Set<String>()
        for note in notes {
            guard note.duration.isFinite, note.duration >= 0,
                  note.createdAt.timeIntervalSince1970.isFinite, note.updatedAt.timeIntervalSince1970.isFinite,
                  note.trashedAt?.timeIntervalSince1970.isFinite != false,
                  validSegments(note.segments), validSegments(note.editedSegments ?? []) else { throw CaptureError.invalid("A capture has invalid dates, duration, or transcript timestamps.") }
            if let name = note.audioFilename {
                _ = try ownedAudioURL(name)
                guard audioNames.insert(name).inserted else { throw CaptureError.invalid("Captures must not share a mutable audio source.") }
            }
        }
    }

    private func validSegments(_ segments: [TranscriptSegment]) -> Bool {
        Set(segments.map(\.id)).count == segments.count &&
            segments.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start }
    }

    private func prepareDirectories() throws {
        for url in [directory, audioDirectory, recordingDraftDirectory, pendingPurgeDirectory] {
            if fm.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw CaptureError.storage("An app storage folder is not a regular directory.") }
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            } else { try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        }
    }

    /// A staged audio file belongs to the old index until the atomic index replacement succeeds.
    /// Restart restores it if still referenced; otherwise it completes the approved deletion.
    private func recoverPendingPurges(referencedBy notes: [CaptureNote]) throws {
        let referenced = Set(notes.compactMap(\.audioFilename))
        for staged in try fm.contentsOfDirectory(at: pendingPurgeDirectory, includingPropertiesForKeys: nil) {
            let destination = try ownedAudioURL(staged.lastPathComponent)
            try requireRegularFile(staged)
            if referenced.contains(staged.lastPathComponent) {
                guard !fm.fileExists(atPath: destination.path) else { throw CaptureError.storage("Both a staged and active audio file exist. Preserve both files and resolve the pending-purge folder before continuing.") }
                try fm.moveItem(at: staged, to: destination)
            } else { try fm.removeItem(at: staged) }
        }
    }

    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CaptureError.invalid("Choose a regular file, rather than a folder or symbolic link.") }
    }

    private func ownedAudioURL(_ filename: String) throws -> URL {
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.lowercased()
        guard filename == (filename as NSString).lastPathComponent, !filename.contains("\\"), UUID(uuidString: stem) != nil,
              Self.audioExtensions.contains(ext) else { throw CaptureError.invalid("The audio reference is unsafe or unsupported.") }
        return audioDirectory.appendingPathComponent(filename)
    }

    private func copyAudio(_ source: URL) throws -> URL {
        guard loaded else { throw CaptureError.notLoaded }
        try prepareDirectories(); try requireRegularFile(source)
        let ext = source.pathExtension.lowercased()
        guard Self.audioExtensions.contains(ext) else { throw CaptureError.invalid("Choose a supported audio file: m4a, wav, mp3, aiff, caf, flac, aac, ogg, or mp4.") }
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= 2_147_483_648 else { throw CaptureError.invalid("Audio files must contain data and be at most 2 GB.") }
        let target = audioDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try fm.copyItem(at: source, to: target)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return target
        }
        catch { try? fm.removeItem(at: target); lastError = error.localizedDescription; throw CaptureError.storage("The original audio could not be copied into the library.") }
    }

    private func rollbackImport(_ target: URL, originalError: Error) throws -> Never {
        do { try fm.removeItem(at: target) }
        catch {
            let issue = CaptureError.storage("The capture was not saved. Cleanup of its copied audio is pending in the app audio folder: \(target.lastPathComponent). The original import is unchanged.")
            lastError = issue.localizedDescription; throw issue
        }
        throw originalError
    }

    private func folded(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
}
