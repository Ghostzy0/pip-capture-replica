import SwiftUI
import AppKit
import AVFoundation
import CaptureCore
import UniformTypeIdentifiers

@MainActor
final class CaptureModel: ObservableObject {
    enum Section: String, CaseIterable { case inbox = "Inbox", favourites = "Favourites", recall = "Find in sources", trash = "Recently deleted" }
    @Published var notes: [CaptureNote] = []
    @Published var edits: [UUID: CaptureNote] = [:]
    @Published var selectedID: UUID?
    @Published var section: Section = .inbox
    @Published var folder = ""
    @Published var query = ""
    @Published var selectedTag = ""
    @Published var message: String?
    @Published var loadFailure = false
    @Published var recordingSheet = false
    @Published var settingsSheet = false
    @Published var aboutSheet = false
    @Published var transcribingID: UUID?
    @Published var recallQuery = ""
    @Published var player: AVAudioPlayer?
    @Published var confirmedSaveCount = 0
    @Published var recoveredDrafts: [RecordingDraft] = []
    let store: CaptureStore
    let recorder: CaptureRecorder
    let edition: AppEdition
    private var transcriber: LocalTranscriber?
    private var transcriptionTask: Task<Void, Never>?
    private var transcriptionGeneration = UUID()
    private var terminationObserver: NSObjectProtocol?

    init(directory: URL? = nil, edition: AppEdition = .current) {
        self.edition = edition
        let root: URL
        if let directory { root = directory }
        else if let path = ProcessInfo.processInfo.environment["PIP_CAPTURE_DATA_DIR"] {
            root = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(edition.storageName, isDirectory: true)
        }
        store = CaptureStore(directory: root)
        recorder = CaptureRecorder(draftsDirectory: root.appendingPathComponent("drafts", isDirectory: true))
        load()
    }
    func load() {
        do { try store.load(); loadFailure = false; refresh(); recoveredDrafts = try store.drafts() }
        catch { loadFailure = true; message = "Your library could not be opened. The saved files are kept. Check the storage folder, then try again." }
    }
    var hasProtectedRecording: Bool { recorder.state == .recording || recorder.state == .paused || recorder.state == .requestingPermission || recorder.draftURL != nil }
    func showSettings() {
        guard !hasProtectedRecording else { message = "Save, keep or discard the recording before opening Settings."; return }
        settingsSheet = true
    }
    func showAbout() {
        guard !hasProtectedRecording else { message = "Save, keep or discard the recording before opening About."; return }
        aboutSheet = true
    }
    func refresh() { notes = store.notes }
    var folders: [String] { Array(Set(notes.filter { $0.trashedAt == nil }.map(\.folder).filter { !$0.isEmpty })).sorted() }
    /// Choices follow folder/favourites/trash scope, independent of query and selected tag.
    var availableTags: [String] {
        guard edition.hasExtras else { return [] }
        let scoped = store.filteredNotes(folder: folder.isEmpty ? nil : folder,
                                         favouritesOnly: section == .favourites, trash: section == .trash)
        return Array(Set(scoped.flatMap(\.tags))).sorted()
    }
    var visibleNotes: [CaptureNote] {
        store.filteredNotes(query: query, folder: folder.isEmpty ? nil : folder,
                            tag: edition.hasExtras && !selectedTag.isEmpty ? selectedTag : nil,
                            favouritesOnly: section == .favourites, trash: section == .trash)
    }
    var selected: CaptureNote? { selectedID.flatMap { id in edits[id] ?? notes.first { $0.id == id } } }
    func edit(_ note: CaptureNote) { edits[note.id] = note }
    func perform(_ failure: String, _ work: () throws -> Void) {
        do { try work(); refresh() } catch { refresh(); message = failure }
    }
    func createText() {
        guard !loadFailure else { return }
        perform("The note could not be created. Check storage space and try again.") {
            let note = try store.createNote(title: "Untitled capture", body: "", tags: [], folder: folder)
            section = .inbox; query = ""; selectedTag = ""; selectedID = note.id
        }
    }
    @discardableResult func save(_ note: CaptureNote) -> Bool {
        do {
            guard var authoritative = store.note(id: note.id) else { return false }
            authoritative.title = note.title; authoritative.body = note.body; authoritative.tags = note.tags
            authoritative.folder = note.folder; authoritative.favourite = note.favourite; authoritative.editedSegments = note.editedSegments
            try store.save(authoritative); edits[note.id] = nil; refresh(); confirmedSaveCount += 1
            message = "Changes saved on this Mac."; return true
        }
        catch { message = "Changes could not be saved. Your edits are kept here. Check storage space and try again."; return false }
    }
    func saveAll() -> Bool {
        for note in Array(edits.values) { if !save(note) { return false } }
        return true
    }
    func toggleFavourite(_ note: CaptureNote) { var updated = note; updated.favourite.toggle(); _ = save(updated) }
    func importFile() {
        guard !loadFailure else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        perform("This file could not be imported. Choose a readable text or audio file and try again.") {
            let isText = ["txt", "md", "markdown"].contains(url.pathExtension.lowercased())
            let note = isText ? try store.importText(from: url) : try store.importAudio(from: url, title: url.deletingPathExtension().lastPathComponent)
            section = .inbox; folder = ""; query = ""; selectedTag = ""; selectedID = note.id
        }
    }
    func trash(_ note: CaptureNote) {
        cancelTranscriptionIfNeeded(note.id); stopPlayback()
        // Save the visible edit before moving it, preserving recovery content.
        if edits[note.id] != nil && !save(note) { return }
        perform("The capture could not be moved. Try again.") { try store.trash(id: note.id); selectedID = nil }
    }
    func restore(_ note: CaptureNote) { perform("The capture could not be restored. Try again.") { try store.restore(id: note.id); section = .inbox; selectedID = note.id } }
    func purge(_ note: CaptureNote) { perform("The capture could not be removed. Check the storage folder and try again.") { try store.purge(id: note.id); edits[note.id] = nil; selectedID = nil } }
    func export(_ note: CaptureNote, audio: Bool) {
        if edits[note.id] != nil && !save(note) { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Export here"; panel.message = audio ? "Choose a folder for the original audio." : "Choose a folder for the Markdown note."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform("The export could not be saved. Choose another folder and try again.") {
            if audio { _ = try store.exportAudio(noteID: note.id, to: url) } else { _ = try store.exportMarkdown(noteID: note.id, to: url) }
            message = "Export saved in the chosen folder."
        }
    }
    func audioURL(_ note: CaptureNote) -> URL? {
        guard let filename = note.audioFilename else { return nil }
        return store.directory.appendingPathComponent("audio", isDirectory: true).appendingPathComponent(filename)
    }
    func play(_ note: CaptureNote, at time: Double = 0) {
        guard let url = audioURL(note) else { return }
        do { player?.stop(); let audio = try AVAudioPlayer(contentsOf: url); player = audio; audio.currentTime = time; audio.play() }
        catch { message = "The original audio could not be played. Your note is kept. Check that the source file is available." }
    }
    func stopPlayback() { player?.stop(); player = nil }
    @discardableResult func saveRecording() -> Bool {
        do {
            let result = try recorder.stop()
            let note = try store.importAudio(from: result.url, title: "Voice capture", duration: result.duration)
            // Original source and duration enter the library in one atomic commit.
            var draftRemains = false
            do { try FileManager.default.removeItem(at: result.url) } catch { draftRemains = true }
            refresh(); refreshDrafts(); section = .inbox; folder = ""; query = ""; selectedTag = ""; selectedID = note.id; recordingSheet = false
            message = draftRemains ? "Audio saved. A draft copy remains in storage for you to inspect." : "Audio saved on this Mac. You can add a transcript when speech files are ready."
            return true
        } catch {
            refresh(); refreshDrafts()
            message = "The recording could not be saved. Its draft is kept in the storage folder for recovery."
            return false
        }
    }
    func refreshDrafts() {
        do { recoveredDrafts = try store.drafts() }
        catch { message = "Recording drafts could not be checked. Open storage to inspect the retained files." }
    }
    func recoverDraft(_ draft: RecordingDraft) {
        perform("The draft could not be recovered. Its source file is kept.") {
            let note = try store.recoverDraft(draft, title: "Recovered voice capture"); try store.discardDraft(draft); recoveredDrafts = try store.drafts()
            section = .inbox; folder = ""; query = ""; selectedTag = ""; selectedID = note.id
        }
    }
    func transcribe(_ note: CaptureNote) {
        guard transcribingID == nil, let url = audioURL(note), note.trashedAt == nil else { return }
        if edits[note.id] != nil && !save(note) { return }
        let defaults = UserDefaults.standard
        let executable = defaults.string(forKey: "speechExecutable") ?? ""
        let weights = defaults.string(forKey: "speechWeights") ?? ""
        guard !executable.isEmpty, !weights.isEmpty else { settingsSheet = true; message = "Choose the local speech files in Settings first. Your audio is already saved."; return }
        let worker = LocalTranscriber(configuration: .init(executableURL: URL(fileURLWithPath: executable), modelURL: URL(fileURLWithPath: weights), language: defaults.string(forKey: "speechLanguage") ?? "auto", workspaceDirectory: store.directory.appendingPathComponent("work", isDirectory: true)))
        let generation = UUID(); transcriptionGeneration = generation; transcriber = worker; transcribingID = note.id
        transcriptionTask = Task {
            defer {
                if transcriptionGeneration == generation { transcribingID = nil; transcriber = nil; transcriptionTask = nil }
            }
            do {
                let result = try await worker.transcribe(audioURL: url)
                guard !Task.isCancelled, transcriptionGeneration == generation else { return }
                guard var current = store.notes.first(where: { $0.id == note.id }), current.trashedAt == nil else { return }
                current.originalTranscript = result.text; current.segments = result.segments; current.transcriptionEngine = result.provenance
                // Preserve edits made while transcription runs. The original remains separately accessible.
                if current.body.isEmpty { current.body = result.text }
                try store.save(current)
                if var pending = edits[note.id] {
                    pending.originalTranscript = current.originalTranscript; pending.segments = current.segments
                    pending.transcriptionEngine = current.transcriptionEngine; edits[note.id] = pending
                }
                refresh(); message = "Transcript saved. Check names, numbers and wording against the audio."
            } catch is CancellationError { }
            catch let failure as LocalTranscriber.TranscriptionError {
                if transcriptionGeneration == generation {
                    switch failure {
                    case .missingTool: message = "The chosen speech tool is missing. Choose it again in Settings. Your audio is kept."; settingsSheet = true
                    case .missingModel: message = "The chosen speech weights are missing. Choose them again in Settings. Your audio is kept."; settingsSheet = true
                    case .timedOut: message = "Transcription took too long. Try a smaller speech file or shorter recording. Your audio is kept."
                    case .cancelled: message = "Transcription stopped. Your audio is kept."
                    case .invalidAudio: message = "This audio could not be read. Try another audio file. Your original is kept."
                    default: message = "Transcription could not finish. Check the speech files and try again. Your original audio is kept."
                    }
                }
            }
            catch { if transcriptionGeneration == generation { message = "Transcription could not finish. Check the speech files and audio, then try again. The original audio is kept." } }
        }
    }
    func applyRetention(_ ids: [UUID]) {
        guard saveAll() else { return }
        if let active = transcribingID, ids.contains(active) { cancelTranscription() }
        stopPlayback()
        perform("These captures could not be moved. Your library is kept.") { try store.applyRetention(noteIDs: ids); selectedID = nil }
    }
    func cancelTranscription() {
        transcriptionGeneration = UUID(); transcriptionTask?.cancel(); transcriptionTask = nil
        let worker = transcriber; transcriber = nil; transcribingID = nil
        Task { await worker?.cancel() }
        message = "Transcription stopped. The original audio is kept."
    }
    func cancelTranscriptionIfNeeded(_ id: UUID) { if transcribingID == id { cancelTranscription() } }
    func revealStorage() { NSWorkspace.shared.open(store.directory) }
}
