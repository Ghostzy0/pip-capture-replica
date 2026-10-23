import SwiftUI
import CaptureCore
import AppKit

struct CaptureView: View {
    @ObservedObject var model: CaptureModel
    @AppStorage("lookTheme") private var lookTheme = "paper"
    @AppStorage("lookMode") private var lookMode = "light"
    @FocusState private var libraryFocused: Bool
    @AppStorage("recorderCollapsed") private var recorderCollapsed = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 0) {
            if let message = model.message {
                HStack(alignment: .top, spacing: CaptureTheme.gap) {
                    Image(systemName: model.loadFailure ? "exclamationmark.triangle" : "info.circle").accessibilityHidden(true)
                    Text(message).textSelection(.enabled).font(CaptureTheme.font(13))
                    Spacer(minLength: 8)
                    if model.loadFailure { Button("Try again") { model.load() } }
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.help("Dismiss message").accessibilityLabel("Dismiss message")
                }.buttonStyle(.plain).padding(CaptureTheme.inset).background(CaptureTheme.fill(scheme))
            }
            HSplitView {
                sidebar.frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
                library.frame(minWidth: 260, idealWidth: 300, maxWidth: 390)
                Group {
                    if model.section == .recall { RecallView(model: model) }
                    else if let note = model.selected { NoteEditor(model: model, id: note.id).id(note.id) }
                    else { emptyDetail }
                }.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if AppEdition.current.hasExtras && model.recordingSheet {
                CompactRecordingControls(model: model, recorder: model.recorder, collapsed: $recorderCollapsed)
                    .background(CaptureTheme.surface(scheme, oat: lookTheme == "oat"))
            }
        }
        .foregroundStyle(CaptureTheme.ink(scheme, oat: lookTheme == "oat"))
        .background(CaptureTheme.canvas(scheme, oat: lookTheme == "oat"))
        .preferredColorScheme(lookMode == "system" ? nil : lookMode == "dark" ? .dark : .light)
        .font(CaptureTheme.font(14))
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: Binding(get: { model.recordingSheet && !AppEdition.current.hasExtras }, set: { model.recordingSheet = $0 })) { RecordingSheet(model: model, recorder: model.recorder) }
        .sheet(isPresented: $model.settingsSheet) { CaptureSettings(model: model) }
        .sheet(isPresented: $model.aboutSheet) { CaptureAbout() }
        .toolbar {
            ToolbarItemGroup {
                Button { model.importFile() } label: { Label("Import", systemImage: "square.and.arrow.down") }.disabled(model.loadFailure)
                Button { model.createText() } label: { Label("New note", systemImage: "square.and.pencil") }.keyboardShortcut("n").disabled(model.loadFailure)
                Button { model.recordingSheet = true } label: { Label("Record", systemImage: "mic") }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.loadFailure)
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: CaptureTheme.section) {
            HStack(spacing: CaptureTheme.small) { PipPebble(busy: model.transcribingID != nil, cue: model.confirmedSaveCount).scaleEffect(0.68).frame(width: 40, height: 40); Text(AppEdition.current.name).font(CaptureTheme.font(20, weight: .semibold)) }
                .padding(.top, CaptureTheme.small)
            VStack(alignment: .leading, spacing: CaptureTheme.small) {
                Text("A place for what matters.").font(CaptureTheme.font(15, weight: .medium))
                Text("Saved on this Mac.").font(CaptureTheme.font(13)).foregroundStyle(CaptureTheme.secondary(scheme))
            }
            VStack(spacing: 4) {
                nav(.inbox, icon: "tray")
                nav(.favourites, icon: "star")
                nav(.recall, icon: "text.magnifyingglass")
            }
            if !model.folders.isEmpty {
                VStack(alignment: .leading, spacing: CaptureTheme.small) {
                    Text("Folders").font(CaptureTheme.font(12, weight: .medium)).foregroundStyle(CaptureTheme.secondary(scheme)).padding(.horizontal, CaptureTheme.small)
                    ScrollView {
                    VStack(spacing: 4) {
                    ForEach(model.folders, id: \.self) { name in
                        Button { model.section = .inbox; model.folder = name; model.selectedID = nil } label: {
                            Label(name, systemImage: "folder").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(CaptureTheme.small)
                                .background(model.folder == name ? CaptureTheme.fill(scheme) : .clear, in: RoundedRectangle(cornerRadius: CaptureTheme.radius))
                        }.buttonStyle(.plain)
                    }
                    }
                    }.frame(maxHeight: 240)
                }
            }
            Spacer(minLength: CaptureTheme.section)
            if !model.recoveredDrafts.isEmpty {
                VStack(alignment: .leading, spacing: CaptureTheme.small) {
                    Text("An unfinished recording was found.").font(CaptureTheme.font(13))
                    Button("Recover recording") { model.recoverDraft(model.recoveredDrafts[0]) }.buttonStyle(CaptureButtonStyle())
                }
            }
            VStack(spacing: 4) {
                nav(.trash, icon: "trash")
                Button { model.showSettings() } label: { Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding(CaptureTheme.small) }.buttonStyle(.plain)
                Button { model.showAbout() } label: { Label("About Capture", systemImage: "info.circle").frame(maxWidth: .infinity, alignment: .leading).padding(CaptureTheme.small) }.buttonStyle(.plain)
            }
            Button { model.recordingSheet = true } label: { Label("Record a thought", systemImage: "mic").frame(maxWidth: .infinity) }.buttonStyle(CaptureButtonStyle(primary: true)).disabled(model.loadFailure)
        }.padding(CaptureTheme.inset).background(CaptureTheme.surface(scheme, oat: lookTheme == "oat"))
    }
    private func nav(_ section: CaptureModel.Section, icon: String) -> some View {
        Button { model.section = section; model.folder = ""; model.selectedID = nil } label: {
            HStack { Image(systemName: icon).frame(width: 20); Text(section.rawValue); Spacer(minLength: 0)
                if section == .inbox { Text("\(model.notes.filter { $0.trashedAt == nil }.count)").font(CaptureTheme.font(12)).monospacedDigit() }
            }.padding(CaptureTheme.small).background(model.section == section && model.folder.isEmpty ? CaptureTheme.fill(scheme) : .clear, in: RoundedRectangle(cornerRadius: CaptureTheme.radius))
        }.buttonStyle(.plain).accessibilityAddTraits(model.section == section && model.folder.isEmpty ? .isSelected : [])
    }
    private var filtering: Bool { !model.query.isEmpty || (AppEdition.current.hasExtras && !model.selectedTag.isEmpty) }
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: CaptureTheme.gap) {
                Text(model.folder.isEmpty ? model.section.rawValue : model.folder).font(CaptureTheme.font(24, weight: .semibold)).lineLimit(2)
                TextField("Search captures", text: $model.query).textFieldStyle(.roundedBorder).accessibilityLabel("Search captures")
                if AppEdition.current.hasExtras {
                    HStack {
                        Picker("Filter by tag", selection: $model.selectedTag) {
                            Text("All tags").tag("")
                            ForEach(model.availableTags, id: \.self) { tag in Text(tag).tag(tag) }
                            if !model.selectedTag.isEmpty && !model.availableTags.contains(model.selectedTag) { Text(model.selectedTag).tag(model.selectedTag) }
                        }.pickerStyle(.menu).accessibilityValue(model.selectedTag.isEmpty ? "All tags" : model.selectedTag)
                        if !model.selectedTag.isEmpty { Button("Clear") { model.selectedTag = "" }.accessibilityLabel("Clear tag filter") }
                    }
                }
                HStack(spacing: CaptureTheme.small) {
                    Button("New note") { model.createText() }.buttonStyle(CaptureButtonStyle()).disabled(model.loadFailure)
                    Button("Import") { model.importFile() }.buttonStyle(CaptureButtonStyle()).disabled(model.loadFailure)
                }
            }.padding(CaptureTheme.inset)
            if model.visibleNotes.isEmpty {
                VStack(alignment: .leading, spacing: CaptureTheme.small) {
                    Text(!filtering ? (model.section == .trash ? "Nothing recently deleted." : model.section == .favourites ? "No favourites yet." : "Your captures belong here.") : "No matching captures.").font(CaptureTheme.font(17, weight: .semibold))
                    Text(!filtering ? (model.section == .trash ? "Captures moved here can be restored until you delete them permanently." : model.section == .favourites ? "Mark a capture with the star to keep it close." : "Record a thought, write a note, or import a file.") : "Try a name, tag, folder or a few words from the note.").foregroundStyle(CaptureTheme.secondary(scheme))
                    if filtering { Button("Clear filters") { model.query = ""; model.selectedTag = "" }.buttonStyle(CaptureButtonStyle()) }
                }.padding(CaptureTheme.inset)
                Spacer()
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.visibleNotes) { note in
                        let selected = model.selectedID == note.id
                        VStack(alignment: .leading, spacing: CaptureTheme.small) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(note.title).font(CaptureTheme.font(15, weight: .semibold)).lineLimit(2)
                                Spacer(minLength: 4)
                                if model.edits[note.id] != nil { Image(systemName: "pencil.circle").accessibilityLabel("Unsaved changes") }
                                if note.favourite { Image(systemName: "star.fill").accessibilityLabel("Favourite") }
                            }
                            Text(note.body.isEmpty ? (note.audioFilename == nil ? "Text capture" : "Original audio saved") : note.body).font(CaptureTheme.font(13)).lineLimit(3).foregroundStyle(selected && libraryFocused ? Color.white : CaptureTheme.secondary(scheme))
                            HStack(spacing: CaptureTheme.small) {
                                Text(note.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                                if note.audioFilename != nil { Label("Audio", systemImage: "waveform") }
                                if !note.tags.isEmpty { Text(note.tags.map { "#\($0)" }.joined(separator: " ")).lineLimit(1) }
                            }.font(CaptureTheme.font(11)).foregroundStyle(selected && libraryFocused ? Color.white : CaptureTheme.secondary(scheme))
                        }.foregroundStyle(selected && libraryFocused ? Color.white : CaptureTheme.ink(scheme, oat: lookTheme == "oat")).padding(.vertical, CaptureTheme.small).tag(note.id)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).focused($libraryFocused)
            }
        }.background(CaptureTheme.canvas(scheme, oat: lookTheme == "oat"))
    }
    private var emptyDetail: some View {
        VStack(spacing: CaptureTheme.inset) {
            PipPebble(busy: false)
            Text("Keep the thought.").font(CaptureTheme.font(26, weight: .semibold))
            Text("Voice, text and the original source.\nReady when you want to come back.").font(CaptureTheme.font(15)).multilineTextAlignment(.center).foregroundStyle(CaptureTheme.secondary(scheme))
            Button("Write a note") { model.createText() }.buttonStyle(CaptureButtonStyle(primary: true)).disabled(model.loadFailure)
            Text("No account needed. Your library works offline.").font(CaptureTheme.font(12)).foregroundStyle(CaptureTheme.secondary(scheme))
        }.padding(CaptureTheme.large).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteEditor: View {
    @ObservedObject var model: CaptureModel
    let id: UUID
    @State private var sourceOpen = false
    @State private var highlightsOpen = false
    @State private var correctionOpen = false
    @State private var confirmingPurge = false
    @State private var tagsText = ""
    @Environment(\.colorScheme) private var scheme
    private var note: CaptureNote? { model.edits[id] ?? model.notes.first { $0.id == id } }
    private func field(_ key: WritableKeyPath<CaptureNote, String>) -> Binding<String> {
        Binding(get: { note?[keyPath: key] ?? "" }, set: { value in if var changed = note { changed[keyPath: key] = value; model.edit(changed) } })
    }
    var body: some View {
        if let note {
            ScrollView {
            VStack(alignment: .leading, spacing: CaptureTheme.inset) {
                HStack(spacing: CaptureTheme.small) {
                    Text(note.trashedAt == nil ? (note.audioFilename == nil ? "Text capture" : "Voice capture") : "Recently deleted").foregroundStyle(CaptureTheme.secondary(scheme))
                    Spacer()
                    if note.trashedAt == nil {
                        Button { model.toggleFavourite(note) } label: { Image(systemName: note.favourite ? "star.fill" : "star") }.help(note.favourite ? "Remove favourite" : "Add favourite").accessibilityLabel(note.favourite ? "Remove favourite" : "Add favourite")
                        Menu { Button("Export Markdown") { model.export(note, audio: false) }; if note.audioFilename != nil { Button("Export original audio") { model.export(note, audio: true) } }; Divider(); Button("Move to recently deleted", role: .destructive) { model.trash(note) } } label: { Label("More", systemImage: "ellipsis") }
                    }
                }.font(CaptureTheme.font(12)).buttonStyle(.borderless)
                TextField("Title", text: field(\.title), axis: .vertical).font(CaptureTheme.font(26, weight: .semibold)).textFieldStyle(.plain).accessibilityLabel("Capture title").disabled(note.trashedAt != nil)
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened)).font(CaptureTheme.font(12)).foregroundStyle(CaptureTheme.secondary(scheme))
                if note.trashedAt != nil {
                    Text("This capture and its audio are kept until you remove them permanently.").font(CaptureTheme.font(14))
                    HStack { Button("Restore capture") { model.restore(note) }.buttonStyle(CaptureButtonStyle(primary: true)); Button("Delete permanently", role: .destructive) { confirmingPurge = true }.buttonStyle(CaptureButtonStyle()) }
                    ScrollView { Text(note.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    if note.audioFilename != nil {
                        HStack(spacing: CaptureTheme.small) {
                            Button { model.play(note) } label: { Label("Play original", systemImage: "play.fill") }.buttonStyle(CaptureButtonStyle())
                            if model.player != nil { Button("Stop") { model.stopPlayback() }.buttonStyle(CaptureButtonStyle()) }
                            Spacer(minLength: 4)
                            if model.transcribingID == id { ProgressView().controlSize(.small); Button("Stop transcription") { model.cancelTranscription() }.buttonStyle(CaptureButtonStyle()) }
                            else { Button(note.originalTranscript == nil ? "Transcribe" : "Transcribe again") { model.transcribe(note) }.buttonStyle(CaptureButtonStyle()).disabled(model.transcribingID != nil) }
                        }
                        Text("Original audio is kept. Transcription runs on this Mac.").font(CaptureTheme.font(12)).foregroundStyle(CaptureTheme.secondary(scheme))
                    }
                    HStack(alignment: .top, spacing: CaptureTheme.inset) {
                        VStack(alignment: .leading, spacing: 4) { Text("Folder").font(CaptureTheme.font(12)); TextField("Inbox", text: field(\.folder)).textFieldStyle(.roundedBorder).accessibilityLabel("Folder") }
                        VStack(alignment: .leading, spacing: 4) { Text("Tags, separated by commas").font(CaptureTheme.font(12)); TextField("ideas, work", text: $tagsText).onChange(of: tagsText) { _, value in
                            guard var changed = self.note else { return }
                            let tags = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                            guard changed.tags != tags else { return }
                            changed.tags = tags; model.edit(changed)
                        }.textFieldStyle(.roundedBorder).accessibilityLabel("Tags, separated by commas") }
                    }
                    Text("Your note").font(CaptureTheme.font(12, weight: .medium)).foregroundStyle(CaptureTheme.secondary(scheme))
                    TextEditor(text: field(\.body)).font(CaptureTheme.font(15)).scrollContentBackground(.hidden).frame(height: CaptureTheme.editorHeight).padding(CaptureTheme.small)
                        .background(CaptureTheme.surface(scheme, oat: false), in: RoundedRectangle(cornerRadius: CaptureTheme.radius))
                        .overlay(RoundedRectangle(cornerRadius: CaptureTheme.radius).stroke(CaptureTheme.line(scheme))).accessibilityLabel("Editable note")
                    HStack(spacing: CaptureTheme.small) {
                        Button("Save changes") { _ = model.save(note) }.buttonStyle(CaptureButtonStyle(primary: true)).keyboardShortcut("s").disabled(model.edits[id] == nil)
                        Text(model.edits[id] == nil ? "Saved on this Mac" : "Unsaved changes").font(CaptureTheme.font(12)).foregroundStyle(CaptureTheme.secondary(scheme))
                        Spacer()
                    }
                    HStack(spacing: CaptureTheme.small) {
                        if !note.segments.isEmpty { Button("Correct transcript") { correctionOpen.toggle() }.buttonStyle(CaptureButtonStyle()) }
                        Button("Source") { sourceOpen.toggle() }.buttonStyle(CaptureButtonStyle())
                        Button("Highlights") { highlightsOpen.toggle() }.buttonStyle(CaptureButtonStyle())
                    }
                    if correctionOpen && !note.segments.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: CaptureTheme.small) {
                                Text("Correct the timed transcript").font(CaptureTheme.font(14, weight: .semibold))
                                Text("Your corrections keep the original timestamps. Source shows the unchanged speech result.").font(CaptureTheme.font(12)).foregroundStyle(.secondary)
                                ForEach(note.editedSegments ?? note.segments) { segment in
                                    HStack(alignment: .top, spacing: CaptureTheme.small) {
                                        Button(timecode(segment.start)) { model.play(note, at: segment.start) }.font(.system(.caption, design: .monospaced))
                                        TextField("Transcript text", text: Binding(get: { (self.note?.editedSegments ?? self.note?.segments ?? []).first { $0.id == segment.id }?.text ?? "" }, set: { value in
                                            guard var changed = self.note else { return }
                                            var corrections = changed.editedSegments ?? changed.segments
                                            if let index = corrections.firstIndex(where: { $0.id == segment.id }) { corrections[index].text = value }
                                            changed.editedSegments = corrections; model.edit(changed)
                                        }), axis: .vertical).textFieldStyle(.roundedBorder).accessibilityLabel("Transcript at \(timecode(segment.start))")
                                    }
                                }
                            }
                        }.frame(maxHeight: CaptureTheme.correctionHeight).padding(CaptureTheme.inset)
                    }
                    if sourceOpen {
                        ScrollView {
                            VStack(alignment: .leading, spacing: CaptureTheme.small) {
                                Text(note.originalTranscript == nil ? "No speech transcript yet. The saved note is your source." : "Original speech transcript").font(CaptureTheme.font(14, weight: .semibold))
                                Text("Edits to your note do not change the original transcript. Speech recognition can make mistakes.").font(CaptureTheme.font(12)).foregroundStyle(CaptureTheme.secondary(scheme))
                                if note.segments.isEmpty { Text(note.originalTranscript ?? note.body).textSelection(.enabled) }
                                ForEach(note.segments) { segment in
                                    HStack(alignment: .top) {
                                        Button(timecode(segment.start)) { model.play(note, at: segment.start) }.font(.system(.caption, design: .monospaced)).help("Play source from this timestamp")
                                        Text(segment.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: CaptureTheme.sourceHeight).padding(CaptureTheme.inset).background(CaptureTheme.surface(scheme, oat: false), in: RoundedRectangle(cornerRadius: CaptureTheme.radius))
                    }
                    if highlightsOpen {
                        ScrollView {
                            VStack(alignment: .leading, spacing: CaptureTheme.small) {
                                Text("Extracts from your saved source").font(CaptureTheme.font(14, weight: .semibold))
                                Text("Selected source sentences. No generated summary.").font(CaptureTheme.font(12)).foregroundStyle(CaptureTheme.secondary(scheme))
                                ForEach(model.store.highlights(for: note)) { excerpt in Text(excerpt.text).textSelection(.enabled) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: CaptureTheme.highlightsHeight)
                    }
                }
            }.padding(CaptureTheme.section)
            }
            .onAppear { tagsText = note.tags.joined(separator: ", ") }
            .confirmationDialog("Delete this capture and its original audio permanently? This cannot be undone.", isPresented: $confirmingPurge, titleVisibility: .visible) {
                Button("Delete permanently", role: .destructive) { model.purge(note) }; Button("Cancel", role: .cancel) { }
            }
        }
    }
}
func timecode(_ seconds: Double) -> String { String(format: "%02d:%02d", max(0, Int(seconds)) / 60, max(0, Int(seconds)) % 60) }

struct RecallView: View {
    @ObservedObject var model: CaptureModel
    var body: some View {
        let result = model.store.recall(query: model.recallQuery, limit: 20)
        VStack(alignment: .leading, spacing: CaptureTheme.inset) {
            Text("Find it in your sources").font(CaptureTheme.font(24, weight: .semibold))
            Text("Search saved words and open the capture they came from. Results quote your sources.")
            TextField("A name, number or phrase", text: $model.recallQuery).textFieldStyle(.roundedBorder).accessibilityLabel("Search source words")
            if model.recallQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("Try a name or a few words you remember.").foregroundStyle(.secondary) }
            else if result.excerpts.isEmpty { Text("No matching source found. Try fewer words or check the original recording.").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: CaptureTheme.section) {
                    ForEach(result.excerpts) { excerpt in
                        VStack(alignment: .leading, spacing: CaptureTheme.small) {
                            Button { model.section = .inbox; model.folder = ""; model.query = ""; model.selectedID = excerpt.noteID } label: { Label(excerpt.noteTitle, systemImage: "doc.text") }.font(CaptureTheme.font(15, weight: .semibold))
                            Text(excerpt.text).textSelection(.enabled)
                            Text(excerpt.label + (excerpt.start.map { " at " + timecode($0) } ?? "")).font(CaptureTheme.font(12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(CaptureTheme.section)
    }
}
