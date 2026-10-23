import Foundation

public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: UUID = UUID(), start: Double, end: Double, text: String) {
        self.id = id; self.start = start; self.end = end; self.text = text
    }
}

public struct CaptureNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var tags: [String]
    public var folder: String
    public var favourite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var audioFilename: String?
    public var duration: Double
    public var segments: [TranscriptSegment]
    /// User corrections are separate from the retained original transcription source.
    public var editedSegments: [TranscriptSegment]?
    public var originalTranscript: String?
    public var transcriptionEngine: String?
    public var trashedAt: Date?

    public init(id: UUID = UUID(), title: String = "Untitled capture", body: String = "",
                tags: [String] = [], folder: String = "Inbox", favourite: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date(), audioFilename: String? = nil,
                duration: Double = 0, segments: [TranscriptSegment] = [], editedSegments: [TranscriptSegment]? = nil,
                originalTranscript: String? = nil, transcriptionEngine: String? = nil,
                trashedAt: Date? = nil) {
        self.id = id; self.title = title; self.body = body; self.tags = tags; self.folder = folder
        self.favourite = favourite; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.audioFilename = audioFilename; self.duration = duration; self.segments = segments
        self.editedSegments = editedSegments
        self.originalTranscript = originalTranscript; self.transcriptionEngine = transcriptionEngine
        self.trashedAt = trashedAt
    }
}

public struct SourceExcerpt: Equatable, Identifiable, Sendable {
    public var id: String { "\(noteID.uuidString):\(segmentID?.uuidString ?? "body"):\(label):\(sourceOrdinal)" }
    public let noteID: UUID
    public let noteTitle: String
    public let segmentID: UUID?
    public let start: Double?
    public let end: Double?
    public let text: String
    public let label: String
    public var sourceOrdinal: Int = 0
}

public struct RecallResult: Equatable, Sendable {
    public let query: String
    public let excerpts: [SourceExcerpt]
    public var hasAnswer: Bool { !excerpts.isEmpty }
    public var message: String {
        hasAnswer ? "Matching source excerpts. No generated answer." : "No matching source found in your saved captures."
    }
}

public struct RecordingDraft: Equatable, Identifiable, Sendable {
    public var id: String { filename }
    public let filename: String
    public let url: URL
    public let modifiedAt: Date
    public let byteCount: Int64
}

public enum CaptureError: LocalizedError {
    case storage(String)
    case corruptIndex(String)
    case invalid(String)
    case noteNotFound
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case .storage(let detail): return "Capture could not finish the file operation. \(detail) Your source files have been preserved."
        case .corruptIndex(let detail): return "Capture could not read its library: \(detail) The existing index has been preserved. Restore a backup or move the index aside before creating a new library."
        case .invalid(let detail): return detail
        case .noteNotFound: return "This capture is no longer in the library."
        case .notLoaded: return "Load the library successfully before saving changes. The existing index has not been replaced."
        }
    }
}
