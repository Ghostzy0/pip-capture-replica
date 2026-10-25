import SwiftUI
import AppKit
import CaptureCore

struct RecordingSheet: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var recorder: CaptureRecorder
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    var onClose: (() -> Void)?
    var onCollapse: (() -> Void)?
    private func close() { if let onClose { onClose() } else { dismiss() } }
    @State private var recordingIssue: String?
    @State private var confirmingDiscard = false
    private var active: Bool { recorder.state == .recording || recorder.state == .paused || recorder.state == .requestingPermission || recorder.draftURL != nil }
    var body: some View {
        Group {
            if embedded { embeddedContent }
            else { modalContent }
        }
        .interactiveDismissDisabled(active)
        .confirmationDialog("Discard this recording? It will not be saved.", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) {
                do { try recorder.cancel(); close() }
                catch { self.recordingIssue = "The draft could not be removed. It is kept for recovery." }
            }
            Button("Keep recording", role: .cancel) { }
        }
    }

    private var modalContent: some View {
        VStack(spacing: CaptureTheme.section) {
            HStack { Text("Voice capture").font(CaptureTheme.font(20, weight: .semibold)); Spacer(); if let onCollapse { Button("Collapse", action: onCollapse).accessibilityLabel("Collapse recording controls") }; Button("Close") { close() }.disabled(active) }
            PipPebble(busy: recorder.state == .recording)
            Text(recorder.state == .recording ? "Listening" : recorder.state == .paused ? "Paused" : "Keep the original.").font(CaptureTheme.font(24, weight: .semibold))
            Text(timecode(recorder.duration)).font(.system(size: 32, weight: .medium, design: .monospaced)).monospacedDigit().accessibilityLabel("Recording duration \(timecode(recorder.duration))")
            ProgressView(value: Double(recorder.meter), total: 1).frame(width: 250).accessibilityLabel("Microphone input level").accessibilityValue("\(Int(recorder.meter * 100)) percent")
            Text("Audio stays on this Mac. Pause whenever you need to.").font(CaptureTheme.font(14)).multilineTextAlignment(.center)
            if let step = recorder.permission.nextStep { Text(step).font(CaptureTheme.font(13)).foregroundStyle(.red).textSelection(.enabled) }
            if let message = recordingIssue ?? recorder.lastError { Text(message).font(CaptureTheme.font(13)).foregroundStyle(.red).textSelection(.enabled) }
            actionControls
            if recorder.state == .requestingPermission { Text("Waiting for microphone access.").font(CaptureTheme.font(13)); ProgressView().controlSize(.small) }
        }.padding(CaptureTheme.large).frame(maxWidth: embedded ? .infinity : 470)

    }

    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: CaptureTheme.gap) {
            HStack {
                Text("Voice capture").font(CaptureTheme.font(18, weight: .semibold))
                Spacer()
                if let onCollapse { Button("Collapse", action: onCollapse).accessibilityLabel("Collapse recording controls") }
                Button("Close") { close() }.disabled(active)
            }
            HStack(spacing: CaptureTheme.inset) {
                PipPebble(busy: recorder.state == .recording)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: CaptureTheme.small) {
                    Text(recorder.state == .recording ? "Listening" : recorder.state == .paused ? "Paused" : "Keep the original.")
                        .font(CaptureTheme.font(16, weight: .semibold))
                    Text(timecode(recorder.duration)).font(.system(size: 26, weight: .medium, design: .monospaced)).monospacedDigit()
                        .accessibilityLabel("Recording duration \(timecode(recorder.duration))")
                    ProgressView(value: Double(recorder.meter), total: 1).frame(maxWidth: 250)
                        .accessibilityLabel("Microphone input level").accessibilityValue("\(Int(recorder.meter * 100)) percent")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Audio stays on this Mac. Pause whenever you need to.")
                .font(CaptureTheme.font(13)).foregroundStyle(CaptureTheme.secondary(scheme))
            if recorder.state == .requestingPermission {
                HStack(spacing: CaptureTheme.small) {
                    Text("Waiting for microphone access.").font(CaptureTheme.font(13))
                    ProgressView().controlSize(.small)
                }
            }
            if recorder.permission.nextStep != nil || recordingIssue != nil || recorder.lastError != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: CaptureTheme.small) {
                        if let step = recorder.permission.nextStep { Text(step).font(CaptureTheme.font(13)).foregroundStyle(.red).textSelection(.enabled) }
                        if let message = recordingIssue ?? recorder.lastError { Text(message).font(CaptureTheme.font(13)).foregroundStyle(.red).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 56)
            }
            actionControls
        }
        .padding(.horizontal, CaptureTheme.inset)
        .padding(.vertical, CaptureTheme.small)
        .frame(maxWidth: .infinity)
    }

    private var actionControls: some View {
        HStack(spacing: CaptureTheme.gap) {
            if recorder.state == .recording || recorder.state == .paused {
                Button(recorder.state == .paused ? "Resume" : "Pause") {
                    do { if recorder.state == .paused { try recorder.resume() } else { try recorder.pause() } }
                    catch { self.recordingIssue = "Recording could not change state. Save the recording or close it safely." }
                }.buttonStyle(CaptureButtonStyle())
                Button("Save recording") { if !model.saveRecording() { recordingIssue = "The recording could not be saved. Its draft is kept. Close this window and use Recover recording in the sidebar." } }.buttonStyle(CaptureButtonStyle(primary: true))
            } else if recorder.state == .failed && recorder.draftURL != nil {
                Button("Keep draft and close") {
                    do { _ = try recorder.keepDraftAndReset(); model.refreshDrafts(); close() }
                    catch { recordingIssue = "The draft could not be detached safely. It is kept in storage. You can quit and recover it when you reopen." }
                }.buttonStyle(CaptureButtonStyle(primary: true))
            } else if !active && recordingIssue == nil {
                Button("Start recording") {
                    Task {
                        do { recordingIssue = nil; try await recorder.requestPermissionAndStart() }
                        catch is CancellationError { }
                        catch { self.recordingIssue = error.localizedDescription }
                    }
                }.buttonStyle(CaptureButtonStyle(primary: true)).disabled(model.loadFailure)
            }
            if !active && recordingIssue != nil { Button("Close and recover later") { close() }.buttonStyle(CaptureButtonStyle(primary: true)) }
            if active { Button("Discard", role: .destructive) { confirmingDiscard = true }.buttonStyle(CaptureButtonStyle()) }
        }
    }
}

struct CaptureSettings: View {
    @ObservedObject var model: CaptureModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lookTheme") private var theme = "paper"
    @AppStorage("lookMode") private var mode = "light"
    @AppStorage("speechExecutable") private var executable = ""
    @AppStorage("speechWeights") private var weights = ""
    @AppStorage("speechLanguage") private var language = "auto"
    @State private var retentionEnabled = false
    @State private var confirmingRetention = false
    @State private var showAdvanced = false
    @State private var workCopyCount = 0
    @State private var workCopyIssue: String?
    @State private var confirmingWorkCleanup = false
    private var retention: [CaptureNote] { model.store.retentionPreview(olderThan: Date().addingTimeInterval(-30 * 86400), enabled: retentionEnabled) }
    var body: some View {
        VStack(alignment: .leading, spacing: CaptureTheme.section) {
            HStack { Text("Settings").font(CaptureTheme.font(24, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: CaptureTheme.section) {
                    GroupBox("Look") {
                        VStack(spacing: CaptureTheme.inset) {
                            if AppEdition.current.isPip { HStack { Text("Theme"); Spacer(); Picker("Theme", selection: $theme) { Text("Paper").tag("paper"); Text("Oat").tag("oat") }.pickerStyle(.segmented).frame(width: 220).labelsHidden() } }
                            HStack { Text("Appearance"); Spacer(); Picker("Appearance", selection: $mode) { Text("Light").tag("light"); Text("Dark").tag("dark"); Text("Device").tag("system") }.pickerStyle(.segmented).frame(width: 260).labelsHidden() }
                            Text("The app follows the Mac’s Reduce Motion setting.").font(CaptureTheme.font(12)).foregroundStyle(.secondary)
                        }.padding(CaptureTheme.small)
                    }
                    GroupBox("Local speech") {
                        VStack(alignment: .leading, spacing: CaptureTheme.gap) {
                            Text("Recording works straight away after microphone access. To turn audio into text, choose the speech files already installed on this Mac.")
                            pathRow("Speech tool", path: executable) { chooseFile { executable = $0 } }
                            pathRow("Speech weights", path: weights) { chooseFile { weights = $0 } }
                            Text("Nothing is downloaded or sent automatically. See the setup guide for verified installation steps.").font(CaptureTheme.font(12)).foregroundStyle(.secondary)
                            Link("Open speech setup guide", destination: URL(string: AppEdition.repositoryURL + "/blob/main/docs/AI-SETUP.md")!)
                            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                                TextField("Whisper language code (auto, en, fr…)", text: $language).textFieldStyle(.roundedBorder).accessibilityLabel("Whisper language code")
                                Text("Advanced: whisper.cpp executable and compatible model files run locally. Only choose a tool you trust.").font(CaptureTheme.font(12)).foregroundStyle(.secondary)
                            }
                        }.font(CaptureTheme.font(13)).padding(CaptureTheme.small)
                    }
                    GroupBox("Storage and recovery") {
                        VStack(alignment: .leading, spacing: CaptureTheme.gap) {
                            Text("Original audio and notes stay in the app’s storage folder. Exports are separate copies. There is no automatic deletion or sync.")
                            Button("Open storage folder") { model.revealStorage() }.buttonStyle(CaptureButtonStyle())
                            Text("Speech work copies are removed when a job finishes. A crash can leave copies here.").font(CaptureTheme.font(12)).foregroundStyle(.secondary)
                            if let workCopyIssue { Text(workCopyIssue).font(CaptureTheme.font(12)).foregroundStyle(.red) }
                            if workCopyCount > 0 { Button("Clear \(workCopyCount) temporary speech copies") { confirmingWorkCleanup = true }.buttonStyle(CaptureButtonStyle()).disabled(model.transcribingID != nil) }
                            Divider()
                            Toggle("Preview captures unchanged for 30 days", isOn: $retentionEnabled)
                            if retentionEnabled {
                                Text("\(retention.count) captures match. Move them to Recently deleted only after reviewing this list.").font(CaptureTheme.font(12))
                                ForEach(retention.prefix(10)) { Text($0.title).font(CaptureTheme.font(12)).lineLimit(1) }
                                if retention.count > 10 { Text("And \(retention.count - 10) more. Review the complete library before proceeding.").font(CaptureTheme.font(12)) }
                                Button("Move \(retention.count) captures to recently deleted") { confirmingRetention = true }.disabled(retention.isEmpty).buttonStyle(CaptureButtonStyle())
                            }
                        }.font(CaptureTheme.font(13)).padding(CaptureTheme.small)
                    }
                }
            }
        }.padding(CaptureTheme.section).frame(width: 640, height: 650)
        .onAppear { refreshWorkCopies() }
        .confirmationDialog("Remove these temporary speech copies? Original recordings and notes are kept.", isPresented: $confirmingWorkCleanup, titleVisibility: .visible) {
            Button("Clear temporary copies", role: .destructive) {
                guard model.transcribingID == nil else { return }
                do { _ = try LocalTranscriber.cleanupWorkspaceCopies(in: model.store.directory.appendingPathComponent("work", isDirectory: true)); refreshWorkCopies() }
                catch { workCopyIssue = "Temporary speech copies could not be removed. Open storage to inspect them." }
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Move the matching captures to Recently deleted? Their audio is kept and they can be restored.", isPresented: $confirmingRetention, titleVisibility: .visible) {
            Button("Move to recently deleted") { let ids = retention.map(\.id); model.applyRetention(ids); retentionEnabled = false }
            Button("Cancel", role: .cancel) { }
        }
    }
    private func refreshWorkCopies() {
        do { workCopyCount = try LocalTranscriber.workspaceCopies(in: model.store.directory.appendingPathComponent("work", isDirectory: true)).count; workCopyIssue = nil }
        catch { workCopyIssue = "Temporary speech copies could not be checked. Open storage to inspect them." }
    }
    private func pathRow(_ title: String, path: String, choose: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.medium); Text(path.isEmpty ? "Choose a local file" : URL(fileURLWithPath: path).lastPathComponent).foregroundStyle(.secondary).lineLimit(1).help(path) }
            Spacer(); Button("Choose…", action: choose).buttonStyle(CaptureButtonStyle()).accessibilityLabel("Choose " + title.lowercased())
        }
    }
    private func chooseFile(_ selected: (String) -> Void) { let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; if panel.runModal() == .OK, let path = panel.url?.path { selected(path) } }
}

struct CaptureAbout: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: CaptureTheme.inset) {
            PipPebble(busy: false)
            Text(AppEdition.displayName).font(CaptureTheme.font(26, weight: .semibold))
            Text("\(AppEdition.displayVersion) · Experimental").font(CaptureTheme.font(13)).foregroundStyle(.secondary)
            Text("A local home for voice and text. Keep the original, edit the note, and find the source again.").multilineTextAlignment(.center)
            Text("Built by Ghostzy0. Original local implementation, informed by the MIT WhisperNotes foundation. No affiliation with Mem or Voicenotes.").font(CaptureTheme.font(12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Link("Source, setup and known limits", destination: URL(string: AppEdition.repositoryURL)!)
            Text("Audio stays on your Mac. Speech files are optional and separately installed. Recognition can make mistakes. This build is ad-hoc signed, not notarised.").font(CaptureTheme.font(12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(CaptureButtonStyle(primary: true)).keyboardShortcut(.cancelAction)
        }.padding(CaptureTheme.large).frame(width: 440)
    }
}
