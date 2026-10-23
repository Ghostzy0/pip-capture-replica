import SwiftUI

/// Plus presentation of the same recorder. Collapsing never stops or detaches its session.
struct CompactRecordingControls: View {
    @ObservedObject var model: CaptureModel
    @ObservedObject var recorder: CaptureRecorder
    @Binding var collapsed: Bool
    @State private var issue: String?
    private var running: Bool { recorder.state == .recording || recorder.state == .paused }
    private var status: String {
        switch recorder.state {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .requestingPermission: return "Waiting for microphone access"
        case .failed: return "Recording needs attention"
        case .idle: return "Ready to record"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if collapsed {
                HStack(spacing: CaptureTheme.gap) {
                    Label(status, systemImage: recorder.state == .paused ? "pause.circle" : "mic")
                        .font(CaptureTheme.font(14, weight: .medium))
                    Text(timecode(recorder.duration)).monospacedDigit().accessibilityLabel("Recording duration \(timecode(recorder.duration))")
                    Spacer(minLength: CaptureTheme.small)
                    if running {
                        Button(recorder.state == .paused ? "Resume" : "Pause") {
                            do { if recorder.state == .paused { try recorder.resume() } else { try recorder.pause() } }
                            catch { issue = "Recording could not change state. Expand the controls to save or recover it." }
                        }.buttonStyle(CaptureButtonStyle())
                        Button("Save recording") { if !model.saveRecording() { issue = "The draft is kept. Expand the controls to recover it." } }.buttonStyle(CaptureButtonStyle(primary: true))
                    }
                    Button("Expand") { collapsed = false }.buttonStyle(CaptureButtonStyle()).keyboardShortcut("r", modifiers: [.command, .option])
                        .accessibilityLabel("Expand recording controls")
                }.padding(CaptureTheme.inset)
                if let message = issue ?? recorder.lastError {
                    Text(message).font(CaptureTheme.font(13)).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, CaptureTheme.inset).padding(.bottom, CaptureTheme.small)
                }
            } else {
                ScrollView {
                    RecordingSheet(model: model, recorder: recorder, embedded: true,
                                   onClose: { model.recordingSheet = false }, onCollapse: { collapsed = true })
                }.frame(maxHeight: 320)
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: recorder.state) { _, state in if state == .failed { collapsed = false } }
    }
}
