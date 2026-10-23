import Foundation
import Darwin

/// Adapted baseline safety fix: UUID exports, checked descendants and no recursive cleanup.
struct MarkdownSync {
    let baseURL: URL
    private let fm = FileManager.default

    init(baseURL: URL? = nil) {
        self.baseURL = (baseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pip Capture Baseline/Markdown", isDirectory: true)).standardizedFileURL
        do { try ensureBase() } catch { print("MarkdownSync: storage unavailable; existing files were preserved.") }
    }

    static func validatedFolderName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..",
              trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil else { return nil }
        return bounded(trimmed, bytes: 200)
    }

    func filename(for transcription: Transcription) -> String {
        let cleaned = cleanedTitle(transcription.title)
        return Self.bounded(cleaned, bytes: 120) + "--" + transcription.id.uuidString + ".md"
    }

    @discardableResult
    func write(_ transcription: Transcription, folderName: String?, previousTitle: String? = nil, previousFolderName: String? = nil) -> Bool {
        perform {
            try ensureBase()
            let dir = try resolveDir(folderName)
            try ensureDirectory(dir)
            let target = try checkedDescendant(dir.appendingPathComponent(filename(for: transcription)))
            if exists(target), !isOwnedFile(target, id: transcription.id) { throw SafetyError.collision }
            guard transcription.duration.isFinite, transcription.duration >= 0, transcription.duration < Double(Int.max) else { throw SafetyError.invalid }
            var lines = ["---", "id: \(transcription.id.uuidString)", "date: \(Self.iso.string(from: transcription.createdAt))"]
            if !transcription.tags.isEmpty {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
                lines.append("tags: " + String(decoding: try encoder.encode(transcription.tags.map(\.name)), as: UTF8.self))
            }
            if transcription.isFavorite { lines.append("favorite: true") }
            if transcription.duration > 0 { lines.append("duration: \(Int(transcription.duration))") }
            lines += ["---", "", "# \(transcription.title)", "", transcription.content, ""]
            // Persist the new export before removing a prior file with this same note identity.
            try lines.joined(separator: "\n").write(to: target, atomically: true, encoding: .utf8)
            var previous = transcription; previous.title = previousTitle ?? transcription.title
            let oldDirectories = try [resolveDir(previousFolderName), resolveDir(folderName)]
            var seen = Set<String>()
            for oldDir in oldDirectories {
                let candidates = [oldDir.appendingPathComponent(filename(for: previous)), oldDir.appendingPathComponent(legacyFilename(previous.title))]
                for candidate in candidates where candidate.standardizedFileURL != target.standardizedFileURL && seen.insert(candidate.path).inserted {
                    let safe = try checkedDescendant(candidate)
                    // Legacy title-only exports migrate only when their own frontmatter ID matches.
                    if exists(safe), isOwnedFile(safe, id: transcription.id) { try fm.removeItem(at: safe) }
                }
            }
        }
    }

    @discardableResult
    func delete(_ transcription: Transcription, folderName: String?) -> Bool {
        perform {
            try ensureBase()
            let dir = try resolveDir(folderName)
            for name in [filename(for: transcription), legacyFilename(transcription.title)] {
                let target = try checkedDescendant(dir.appendingPathComponent(name))
                if exists(target), isOwnedFile(target, id: transcription.id) { try fm.removeItem(at: target) }
            }
        }
    }

    @discardableResult
    func createFolderDir(_ name: String) -> Bool {
        perform {
            try ensureBase(); let dir = try folderURL(name)
            guard !exists(dir) else { throw SafetyError.collision }
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
    }

    @discardableResult
    func renameFolderDir(from oldName: String, to newName: String) -> Bool {
        perform {
            try ensureBase()
            let oldDir = try folderURL(oldName), newDir = try folderURL(newName)
            try requireDirectory(oldDir)
            if oldDir == newDir { return }
            guard !exists(newDir) else { throw SafetyError.collision }
            try fm.moveItem(at: oldDir, to: newDir)
        }
    }

    /// Preflight every move, roll back failures, and remove only an empty folder with rmdir.
    @discardableResult
    func deleteFolderDir(_ name: String) -> Bool {
        perform {
            try ensureBase(); let dir = try folderURL(name); try requireDirectory(dir)
            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let moves = try files.map { file -> (URL, URL) in
                let source = try checkedDescendant(file); try requireRegularFile(source)
                guard source.pathExtension.lowercased() == "md" else { throw SafetyError.unknownContents }
                let destination = try checkedDescendant(baseURL.appendingPathComponent(source.lastPathComponent))
                guard !exists(destination) else { throw SafetyError.collision }
                return (source, destination)
            }
            var moved: [(URL, URL)] = []
            do {
                for (source, destination) in moves { try fm.moveItem(at: source, to: destination); moved.append((source, destination)) }
                guard Darwin.rmdir(dir.path) == 0 else { throw SafetyError.unknownContents }
            } catch {
                // Failed rollback still preserves both files; no recursive deletion occurs.
                for (source, destination) in moved.reversed() where !exists(source) { try? fm.moveItem(at: destination, to: source) }
                throw error
            }
        }
    }

    private enum SafetyError: Error { case invalid, collision, unknownContents }
    private func perform(_ operation: () throws -> Void) -> Bool {
        do { try operation(); return true }
        catch { print("MarkdownSync: operation could not finish safely; existing source files were preserved."); return false }
    }
    private func ensureBase() throws {
        if !exists(baseURL) { try fm.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try requireDirectory(baseURL)
    }
    private func resolveDir(_ folderName: String?) throws -> URL {
        if let folderName { return try folderURL(folderName) }; return baseURL
    }
    private func folderURL(_ name: String) throws -> URL {
        guard let safe = Self.validatedFolderName(name) else { throw SafetyError.invalid }
        return try checkedDescendant(baseURL.appendingPathComponent(safe, isDirectory: true))
    }
    private func ensureDirectory(_ directory: URL) throws {
        if directory == baseURL { try requireDirectory(directory); return }
        _ = try checkedDescendant(directory)
        if !exists(directory) { try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        try requireDirectory(directory)
    }
    private func checkedDescendant(_ candidate: URL) throws -> URL {
        let url = candidate.standardizedFileURL
        let root = baseURL.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path != root, path.hasPrefix(root + "/") else { throw SafetyError.invalid }
        if exists(url), (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { throw SafetyError.invalid }
        return url
    }
    private func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw SafetyError.invalid }
    }
    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw SafetyError.invalid }
    }
    private func isOwnedFile(_ url: URL, id: UUID) -> Bool {
        guard (try? requireRegularFile(url)) != nil, let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.hasPrefix("---\nid: \(id.uuidString)\n")
    }
    private func exists(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
    private func cleanedTitle(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let text = String(String.UnicodeScalarView(title.unicodeScalars.filter { !invalid.contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "." || text == ".." ? "untitled" : text
    }
    private func legacyFilename(_ title: String) -> String { Self.bounded(cleanedTitle(title), bytes: 200) + ".md" }
    private static func bounded(_ value: String, bytes: Int) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            guard result.utf8.count + String(scalar).utf8.count <= bytes else { break }; result.unicodeScalars.append(scalar)
        }
        return result
    }
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]; return formatter
    }()
}
