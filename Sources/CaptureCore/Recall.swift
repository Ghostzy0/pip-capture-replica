import Foundation

extension CaptureStore {
    /// Keyword retrieval over retained sources. This deliberately never synthesizes an answer.
    public func recall(query: String, limit: Int = 8) -> RecallResult {
        let stopwords: Set<String> = ["a", "an", "the", "is", "are", "was", "were", "what", "where", "when", "who", "why", "how", "did", "do", "does", "my", "i", "we", "you", "our", "and", "or", "to", "of", "in", "on", "for", "it", "that", "this", "about", "please", "find", "me"]
        let terms = Set(searchFold(query).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stopwords.contains($0) })
        guard !terms.isEmpty, limit > 0 else { return RecallResult(query: query, excerpts: []) }
        var matches: [(SourceExcerpt, Int, Date)] = []
        for note in notes where note.trashedAt == nil {
            for excerpt in sourceExcerpts(note) {
                let text = searchFold(excerpt.text)
                let score = terms.filter { text.contains($0) }.count
                if score > 0 { matches.append((excerpt, score, note.updatedAt)) }
            }
        }
        matches.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.2 != rhs.2 { return lhs.2 > rhs.2 }
            return lhs.0.id < rhs.0.id
        }
        return RecallResult(query: query, excerpts: Array(matches.prefix(min(limit, 100))).map { $0.0 })
    }

    public func highlights(for note: CaptureNote, limit: Int = 3) -> [SourceExcerpt] {
        guard note.trashedAt == nil, limit > 0 else { return [] }
        return Array(sourceExcerpts(note).prefix(min(limit, 20))).map {
            SourceExcerpt(noteID: $0.noteID, noteTitle: $0.noteTitle, segmentID: $0.segmentID,
                          start: $0.start, end: $0.end, text: $0.text,
                          label: "Extractive highlight · " + $0.label, sourceOrdinal: $0.sourceOrdinal)
        }
    }

    private func sourceExcerpts(_ note: CaptureNote) -> [SourceExcerpt] {
        var result = note.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
            SourceExcerpt(noteID: note.id, noteTitle: note.title, segmentID: $0.id,
                          start: $0.start, end: $0.end, text: $0.text, label: "Original transcript segment")
        }
        result += (note.editedSegments ?? []).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
            SourceExcerpt(noteID: note.id, noteTitle: note.title, segmentID: $0.id,
                          start: $0.start, end: $0.end, text: $0.text, label: "Edited transcript segment · user correction")
        }
        // Keep the editable note and original transcript distinct, even when they diverge.
        let sources: [(String, String)] = [(note.body, "Note text")] +
            (note.segments.isEmpty && note.originalTranscript != note.body ? [(note.originalTranscript ?? "", "Original transcript")] : [])
        for (body, label) in sources {
            for (index, paragraph) in body.components(separatedBy: .newlines).enumerated() where !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(SourceExcerpt(noteID: note.id, noteTitle: note.title, segmentID: nil,
                                            start: nil, end: nil, text: paragraph, label: label, sourceOrdinal: index))
            }
        }
        return result
    }

    private func searchFold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
