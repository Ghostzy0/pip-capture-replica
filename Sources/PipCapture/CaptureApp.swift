import SwiftUI
import AppKit

final class CaptureAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: CaptureModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.recorder.state == .recording || model.recorder.state == .paused || model.recorder.state == .requestingPermission {
            model.recordingSheet = true; model.message = "Save or discard the recording before quitting."; return .terminateCancel
        }
        guard model.saveAll() else { return .terminateCancel }
        model.cancelTranscriptionIfNeeded(model.transcribingID ?? UUID()); model.stopPlayback()
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model else { return true }
        if model.recorder.state == .recording || model.recorder.state == .paused || model.recorder.state == .requestingPermission || model.recorder.draftURL != nil {
            model.recordingSheet = true; model.message = "Save, keep or discard the recording before closing the window."; return false
        }
        guard model.saveAll() else { return false }
        model.cancelTranscription(); model.stopPlayback(); return true
    }
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
}
struct PipCaptureApp: App {
    @NSApplicationDelegateAdaptor(CaptureAppDelegate.self) var delegate
    @StateObject private var model = CaptureModel()
    init() { CaptureTheme.registerFonts() }
    var body: some Scene {
        Window(AppEdition.displayName, id: "capture") {
            Group {
                if AppEdition.isReplica { ReplicaView(model: model) } else { CaptureView(model: model) }
            }.onAppear { delegate.model = model; NSApp.windows.first(where: { $0.isVisible })?.delegate = delegate }
        }.defaultSize(width: 1200, height: 760).windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About \(AppEdition.displayName)") { model.showAbout() } }
            CommandGroup(replacing: .newItem) { Button("New text capture") { model.createText() }.keyboardShortcut("n"); Button("Import text or audio…") { model.importFile() }.keyboardShortcut("i", modifiers: [.command, .shift]) }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { model.showSettings() }.keyboardShortcut(",") }
            CommandMenu("Capture") { Button("Record…") { model.recordingSheet = true }.keyboardShortcut("r", modifiers: [.command, .shift]); Button("Save changes") { if let note = model.selected { _ = model.save(note) } }.keyboardShortcut("s"); Button("Stop transcription") { model.cancelTranscription() }.disabled(model.transcribingID == nil) }
        }
    }
}
