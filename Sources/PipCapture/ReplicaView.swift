import SwiftUI
import CaptureCore

/// Original, evidence-limited Voicenotes workflow adaptation. See docs/REPLICA-SCOPE.md.
/// Selected only by the separate replica bundle configuration.
struct ReplicaView: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.colorScheme) private var scheme

    private var title: String {
        switch model.section {
        case .inbox: return "Home"
        case .recall: return "Find in notes"
        case .favourites: return "Favourites"
        case .trash: return "Recently deleted"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = model.message {
                HStack(alignment: .top) {
                    Text(message).textSelection(.enabled)
                    Spacer()
                    if model.loadFailure { Button("Try again") { model.load() } }
                    Button("Dismiss") { model.message = nil }
                }.padding(12).background(Color(nsColor: .controlBackgroundColor))
            }
            HSplitView {
                navigation.frame(minWidth: 190, idealWidth: 210, maxWidth: 240)
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    if model.section == .recall {
                        RecallView(model: model)
                    } else if let note = model.selected {
                        HStack {
                            Button { model.selectedID = nil } label: { Label("Back to \(title)", systemImage: "chevron.left") }
                            Spacer()
                        }.padding(.horizontal, 24).padding(.top, 16)
                        NoteEditor(model: model, id: note.id).id(note.id)
                    } else {
                        library
                    }
                }.frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Color.primary)
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 780, minHeight: 580)
        .sheet(isPresented: $model.recordingSheet) { RecordingSheet(model: model, recorder: model.recorder) }
        .sheet(isPresented: $model.settingsSheet) { CaptureSettings(model: model) }
        .sheet(isPresented: $model.aboutSheet) { CaptureAbout() }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Capture Replica").font(.system(size: 18, weight: .semibold)).padding(.top, 12)
            VStack(spacing: 4) {
                destination(.inbox, label: "Home", icon: "house")
                destination(.recall, label: "Find in notes", icon: "magnifyingglass")
                destination(.favourites, label: "Favourites", icon: "star")
            }
            Spacer()
            if let draft = model.recoveredDrafts.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unfinished recording").font(.system(size: 12, weight: .semibold))
                    Button("Recover recording") { model.recoverDraft(draft) }.disabled(model.loadFailure)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                destination(.trash, label: "Recently deleted", icon: "trash")
                Button { model.showSettings() } label: { Label("Settings", systemImage: "gearshape") }
                Button { model.showAbout() } label: { Label("About", systemImage: "info.circle") }
            }.buttonStyle(.borderless)
            Text("Local experimental edition").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).background(Color(nsColor: .windowBackgroundColor))
    }

    private func destination(_ section: CaptureModel.Section, label: String, icon: String) -> some View {
        Button {
            model.section = section; model.folder = ""; model.selectedTag = ""; model.query = ""; model.selectedID = nil
        } label: {
            Label(label, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(model.section == section ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).accessibilityAddTraits(model.section == section ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(title).font(.system(size: 26, weight: .semibold))
            Spacer()
            Button { model.createText() } label: { Label("New note", systemImage: "square.and.pencil") }
                .disabled(model.loadFailure)
            Button { model.recordingSheet = true } label: {
                Label("Record", systemImage: "record.circle.fill")
                    .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                    .foregroundStyle(.white).background(Color(red: 0.76, green: 0.12, blue: 0.14), in: Capsule())
            }.buttonStyle(.plain).keyboardShortcut("n", modifiers: [.option]).disabled(model.loadFailure)
        }.padding(24)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Search notes", text: $model.query).textFieldStyle(.roundedBorder).accessibilityLabel("Search notes")
            if model.visibleNotes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.query.isEmpty ? (model.section == .trash ? "No deleted notes" : "Your notes start here") : "No matching notes")
                        .font(.system(size: 20, weight: .semibold))
                    Text(model.query.isEmpty ? "Record a memo or write a note. The original audio stays with your note on this Mac." : "Try a title, tag or words from a note.")
                        .foregroundStyle(.secondary)
                    if !model.query.isEmpty { Button("Clear search") { model.query = "" } }
                }.padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.visibleNotes) { note in
                            Button { model.selectedID = note.id } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        Spacer()
                                        if note.audioFilename != nil { Label(timecode(note.duration), systemImage: "waveform") }
                                        if model.edits[note.id] != nil { Label("Unsaved", systemImage: "pencil") }
                                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                                    Text((model.edits[note.id] ?? note).title).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                                    Text((model.edits[note.id] ?? note).body.isEmpty ? (note.audioFilename == nil ? "Text note" : "Original recording saved") : (model.edits[note.id] ?? note).body)
                                        .foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                                    if !note.tags.isEmpty { Text(note.tags.map { "#\($0)" }.joined(separator: " ")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(24)
    }
}
