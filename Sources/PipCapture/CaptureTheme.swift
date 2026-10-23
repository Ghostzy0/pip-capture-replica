import SwiftUI
import CoreText

// Original native adaptation of the supplied Paper tokens. No reserved motion code.
enum CaptureTheme {
    static let small: CGFloat = 8, gap: CGFloat = 12, inset: CGFloat = 16, section: CGFloat = 24, large: CGFloat = 32
    static let radius: CGFloat = 14, control: CGFloat = 34
    static let editorHeight: CGFloat = 260, sourceHeight: CGFloat = 200, correctionHeight: CGFloat = 220, highlightsHeight: CGFloat = 150
    static func canvas(_ scheme: ColorScheme, oat: Bool) -> Color { if !AppEdition.current.isPip { return Color(nsColor: .textBackgroundColor) }; return Color(hex: scheme == .dark ? (oat ? 0x181512 : 0x0F0F0E) : (oat ? 0xF6F2EA : 0xFFFFFF)) }
    static func ink(_ scheme: ColorScheme, oat: Bool) -> Color { if !AppEdition.current.isPip { return Color(nsColor: .labelColor) }; return Color(hex: scheme == .dark ? (oat ? 0xF2EDE3 : 0xF1F1EE) : (oat ? 0x1E1B16 : 0x121211)) }
    static func surface(_ scheme: ColorScheme, oat: Bool) -> Color { if !AppEdition.current.isPip { return Color(nsColor: .windowBackgroundColor) }; return Color(hex: scheme == .dark ? (oat ? 0x211E18 : 0x171716) : (oat ? 0xEFEAE0 : 0xFAFAFA)) }
    static func fill(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x2C2C2B : 0xEBEBEB) }
    static func secondary(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xA3A3A0 : 0x555555) }
    static func line(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x3C3C3B : 0xDEDEDE) }
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { AppEdition.current.isPip ? .custom("Geist", size: size).weight(weight) : .system(size: size, weight: weight) }
    static func registerFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}
extension Color {
    init(hex: UInt) { self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1) }
}
struct PipPebble: View {
    let busy: Bool
    var cue = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
        if AppEdition.current.isPip { ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(CaptureTheme.ink(scheme, oat: false)).rotationEffect(.degrees(-8))
            HStack(spacing: 9) {
                Capsule().frame(width: 5, height: busy ? 12 : 8)
                Capsule().frame(width: 5, height: busy ? 12 : 8)
            }.foregroundStyle(CaptureTheme.canvas(scheme, oat: false)).offset(x: 5, y: -1)
        }.frame(width: 56, height: 50).accessibilityHidden(true)
        .phaseAnimator([false, true, false], trigger: cue) { content, raised in
            content.offset(y: raised && !reduceMotion ? -4 : 0)
        } animation: { _ in .easeOut(duration: reduceMotion ? 0 : 0.12) }
        } else { Image(systemName: "waveform").font(.system(size: 32)).frame(width: 56, height: 50).accessibilityHidden(true) }
        }
    }
}
struct CaptureButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(CaptureTheme.font(13, weight: .medium))
            .padding(.horizontal, CaptureTheme.inset).frame(minHeight: CaptureTheme.control)
            .background(primary ? CaptureTheme.ink(scheme, oat: false) : CaptureTheme.fill(scheme), in: RoundedRectangle(cornerRadius: AppEdition.current.isPip ? 999 : 6))
            .foregroundStyle(primary ? CaptureTheme.canvas(scheme, oat: false) : CaptureTheme.ink(scheme, oat: false))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && AppEdition.current.isPip && !reduceMotion ? 0.97 : 1)
    }
}
