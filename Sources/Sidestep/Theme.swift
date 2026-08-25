import SwiftUI
import CoreText

/// Flight Deck palette + type. Mirrors mockups/flight-deck.html tokens.
enum FD {
    // kode-rust tokens (src/index.css :root), HSL channels → Color. Hue-220 blue-grey + Claude orange.
    static let bg      = Color(hsl: 220, 16, 8)      // --background
    static let bg2     = Color(hsl: 220, 14, 11)     // --background-panel
    static let surface = Color(hsl: 220, 12, 14)     // --background-surface
    static let hover   = Color(hsl: 220, 10, 18)     // --background-hover
    static let line    = Color.white.opacity(0.12)   // glass-mode border
    static let line2   = Color.white.opacity(0.07)
    static let divider = Color.white.opacity(0.16)
    static let ink     = Color(hsl: 220, 10, 93)     // --foreground
    static let ink2    = Color(hsl: 220, 8, 72)      // --foreground-muted
    static let ink3    = Color(hsl: 220, 6, 52)      // --foreground-dim
    static let ink4    = Color(hsl: 220, 6, 40)      // --status-done
    static let accent  = Color(hsl: 25, 95, 55)      // --accent (Claude orange)
    static let accentMuted = Color(hsl: 25, 60, 30)  // --accent-muted
    static let ok      = Color(hsl: 220, 8, 72)      // normal fill: quiet, neutral (no arcade green)
    static let warn    = Color(hsl: 38, 92, 50)      // --warning
    static let crit    = Color(hsl: 0, 70, 55)       // --status-error
    static let info    = Color(hsl: 25, 95, 55)      // highlights / NOW / tooltip = accent
    static let model   = Color(hsl: 25, 85, 58)      // model-scoped bucket: accent, slightly lifted
    static let segOff  = Color.white.opacity(0.07)
    static let track   = Color.white.opacity(0.10)
    static let pctInk  = Color(hsl: 220, 10, 93)
    static let active  = accent                      // knob core, lit gate, active name

    static func severity(_ p: Double) -> Color { p < 50 ? ok : p < 80 ? warn : crit }

    enum Weight { case regular, medium, semibold }
    static func mono(_ size: CGFloat, _ w: Weight = .regular) -> Font {
        let name: String
        switch w { case .regular: name = "IBMPlexMono"; case .medium: name = "IBMPlexMono-Medium"; case .semibold: name = "IBMPlexMono-SemiBold" }
        return fontsLoaded ? Font.custom(name, size: size) : .system(size: size, weight: w == .regular ? .regular : w == .medium ? .medium : .semibold, design: .monospaced)
    }
    static func sans(_ size: CGFloat, _ w: Weight = .regular) -> Font {
        let name: String
        switch w { case .regular: name = "IBMPlexSansCond"; case .medium: name = "IBMPlexSansCond-Medium"; case .semibold: name = "IBMPlexSansCond-SemiBold" }
        return fontsLoaded ? Font.custom(name, size: size) : .system(size: size, weight: w == .regular ? .regular : w == .medium ? .medium : .semibold)
    }

    private(set) static var fontsLoaded = false
    /// Register the bundled IBM Plex TTFs (Contents/Resources/Fonts). Falls back to system fonts if missing.
    static func loadFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var any = false
        for f in files where f.pathExtension == "ttf" {
            if CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil) { any = true }
        }
        fontsLoaded = any
    }
}

extension Color {
    /// HSL (as kode-rust declares tokens: `220 16% 8%`).
    init(hsl h: Double, _ sPct: Double, _ lPct: Double, alpha: Double = 1) {
        let s = sPct / 100, l = lPct / 100
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: alpha)
    }
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

/// macOS-style glass button: translucent gradient over material, top highlight, soft shadow.
struct GlassButtonStyle: ButtonStyle {
    enum Tint { case neutral, ok, warn }
    var tint: Tint = .neutral
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let base: Color = tint == .ok ? FD.accent : tint == .warn ? FD.warn : .white
        let hi = tint == .neutral ? 0.14 : 0.32, lo = tint == .neutral ? 0.05 : 0.12
        let fg: Color = tint == .ok ? Color(hsl: 25, 90, 88) : tint == .warn ? Color(hsl: 38, 80, 88) : FD.ink
        configuration.label
            .font(FD.mono(9.5, .semibold)).tracking(1.3)
            .foregroundStyle(fg)
            .padding(.horizontal, compact ? 0 : 10).padding(.vertical, compact ? 0 : 4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [base.opacity(configuration.isPressed ? lo * 0.5 : hi), base.opacity(configuration.isPressed ? lo * 0.4 : lo)], startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(tint == .neutral ? Color.white.opacity(0.14) : base.opacity(0.5), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.2), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .shadow(color: tint == .neutral ? .clear : base.opacity(0.2), radius: 7)
            .offset(y: configuration.isPressed ? 0.5 : 0)
    }
}

/// Solid tag with the same box metrics as a glass button (so columns stay level).
struct Tag: View {
    var text: String; var color: Color
    var body: some View {
        Text(text).font(FD.mono(9.5, .semibold)).tracking(1.3).foregroundStyle(FD.bg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(color))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.clear, lineWidth: 1))
    }
}

/// 24-segment LED ladder. When `activity` is true, the next unlit segment blinks —
/// "something is burning this budget right now".
struct Ladder: View {
    var percent: Double
    var color: Color
    var thin = false
    var activity = false

    var body: some View {
        let n = 24
        let on = percent > 0 ? max(1, Int((percent / 100 * Double(n)).rounded())) : 0
        TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
            let blinkOn = activity && Int(ctx.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
            Canvas { g, size in
                let gap: CGFloat = 2
                let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                for i in 0..<n {
                    let r = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: size.height)
                    let p = Path(roundedRect: r, cornerRadius: 1)
                    if i < on {
                        g.fill(p, with: .color(color))
                        g.addFilter(.shadow(color: color.opacity(0.45), radius: 3))
                        g.fill(p, with: .color(color))
                        g.addFilter(.shadow(color: .clear, radius: 0))
                    } else if i == on && blinkOn {
                        g.fill(p, with: .color(FD.accent.opacity(0.85)))
                        g.addFilter(.shadow(color: FD.accent.opacity(0.5), radius: 3))
                        g.fill(p, with: .color(FD.accent.opacity(0.85)))
                        g.addFilter(.shadow(color: .clear, radius: 0))
                    } else {
                        g.fill(p, with: .color(FD.segOff))
                    }
                }
            }
            .frame(height: thin ? 6 : 10)
        }
    }
}

extension Date {
    /// "TUE 7P" / "2:09P" style, uppercased.
    func fdDayHour() -> String { formatted(.dateTime.weekday(.abbreviated).hour(.defaultDigits(amPM: .narrow))).uppercased().replacingOccurrences(of: " P", with: "P").replacingOccurrences(of: " A", with: "A") }
    func fdClock() -> String { formatted(.dateTime.hour(.defaultDigits(amPM: .narrow)).minute()).uppercased().replacingOccurrences(of: " P", with: "P").replacingOccurrences(of: " A", with: "A") }
    /// "Tuesday at 7 PM" / "Today at 2:09 PM" — for tooltips.
    func fdSpoken() -> String {
        let cal = Calendar.current
        let day = cal.isDateInToday(self) ? "Today" : cal.isDateInTomorrow(self) ? "Tomorrow" : formatted(.dateTime.weekday(.wide))
        let time = cal.component(.minute, from: self) == 0
            ? formatted(.dateTime.hour(.defaultDigits(amPM: .wide)))
            : formatted(.dateTime.hour(.defaultDigits(amPM: .wide)).minute())
        return "\(day) at \(time)"
    }
    func fdCountdown() -> String {
        let s = max(0, Int(timeIntervalSinceNow))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)D \(h)H" }
        if h > 0 { return "\(h)H \(String(format: "%02d", m))M" }
        return "\(m)M"
    }
}

// MARK: - Custom hover tooltip (instant, Flight Deck styled)

struct TooltipInfo: Equatable {
    var text: String
    var anchor: Anchor<CGRect>
    static func == (a: TooltipInfo, b: TooltipInfo) -> Bool { a.text == b.text }
}

struct TooltipKey: PreferenceKey {
    static var defaultValue: TooltipInfo? = nil
    static func reduce(value: inout TooltipInfo?, nextValue: () -> TooltipInfo?) { if let n = nextValue() { value = n } }
}

/// Attach to any view: `.fdTooltip("Tuesday at 7 PM")`. Shows after a 100 ms hover debounce, hides on exit.
struct FDTooltipModifier: ViewModifier {
    let text: String
    @State private var hovering = false
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .onHover { h in
                hovering = h
                if h {
                    Task { try? await Task.sleep(nanoseconds: 100_000_000); if hovering { shown = true } }
                } else { shown = false }
            }
            .anchorPreference(key: TooltipKey.self, value: .bounds) { shown ? TooltipInfo(text: text, anchor: $0) : nil }
    }
}
extension View { func fdTooltip(_ text: String) -> some View { modifier(FDTooltipModifier(text: text)) } }

/// Root-level layer that renders the current tooltip above its anchor.
struct TooltipLayer: View {
    let info: TooltipInfo?
    var body: some View {
        GeometryReader { geo in
            if let info {
                let r = geo[info.anchor]
                let bubbleW = CGFloat(info.text.count) * 6.4 + 20
                let x = min(max(r.midX, bubbleW / 2 + 4), geo.size.width - bubbleW / 2 - 4)
                VStack(spacing: 0) {
                    Text(info.text)
                        .font(FD.mono(10, .medium)).tracking(0.3).foregroundStyle(FD.ink)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 6).fill(FD.bg.opacity(0.85))
                            }
                        )
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.14), lineWidth: 1))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                        .fixedSize()
                    Triangle().fill(FD.bg.opacity(0.95)).frame(width: 10, height: 5)
                        .offset(x: r.midX - x)   // caret stays over the cell even when the bubble is clamped
                }
                .position(x: x, y: r.minY - 16)
                .transition(.opacity.combined(with: .offset(y: 3)))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.12), value: info)
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); p.move(to: .init(x: r.minX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.minY)); p.addLine(to: .init(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
    }
}
