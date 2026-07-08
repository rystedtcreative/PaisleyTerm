import SwiftUI
import AppKit

// MARK: - Hex initializers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8)  & 0xFF) / 255.0
        let b = Double(rgb         & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8)  & 0xFF) / 255.0
        let b = CGFloat(rgb         & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Dracula Color Palette

extension Color {
    static let draculaBg          = Color(hex: "282a36")
    static let draculaCurrentLine = Color(hex: "44475a")
    static let draculaFg          = Color(hex: "f8f8f2")
    static let draculaComment     = Color(hex: "6272a4")
    static let draculaCyan        = Color(hex: "8be9fd")
    static let draculaGreen       = Color(hex: "50fa7b")
    static let draculaOrange      = Color(hex: "ffb86c")
    static let draculaPink        = Color(hex: "ff79c6")
    static let draculaPurple      = Color(hex: "bd93f9")
    static let draculaRed         = Color(hex: "ff5555")
    static let draculaYellow      = Color(hex: "f1fa8c")
}

extension NSColor {
    static let draculaBg = NSColor(hex: "282a36")
}

// MARK: - Fira Code Font Helpers

extension Font {
    static func firaCode(_ size: CGFloat) -> Font {
        .custom("FiraCode-Regular", size: size)
    }

    static func firaCodeMedium(_ size: CGFloat) -> Font {
        .custom("FiraCode-Medium", size: size)
    }

    static func firaCodeSemiBold(_ size: CGFloat) -> Font {
        .custom("FiraCode-SemiBold", size: size)
    }
}

extension NSFont {
    static func firaCode(size: CGFloat) -> NSFont {
        if let f = NSFont(name: "FiraCode-Regular", size: size) { return f }
        if let f = NSFont(name: "FiraCode-Retina",  size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - Shared vibrancy tint opacity

/// Single source of truth for the Dracula dark tint used on every pane.
/// Change this one value to tune transparency app-wide.
let draculaTintOpacity: CGFloat = 0.72

/// Corner radius for the floating detail-pane glass card. Tuned to read alongside the
/// macOS 26 Liquid Glass sidebar card.
let cardCornerRadius: CGFloat = 11

/// Dark tint for the floating glass cards — lower than `draculaTintOpacity` so much more
/// of the behind-window blur shows through, for a pronounced glassy look.
let cardTintOpacity: CGFloat = 0.42

/// Margins that float the detail-pane card inside the detail column. Leading is small
/// (the split divider already provides a gap to the sidebar); the other edges float it
/// off the window frame so the translucent window shows around it like the sidebar card.
let detailCardInsets = EdgeInsets(top: 6, leading: 6, bottom: 9, trailing: 6)

// MARK: - Shared vibrancy background

/// NSVisualEffectView with .behindWindow blending — requires window.isOpaque = false.
///
/// `cardStyle` clips the blur to a fully-rounded card via `maskImage` — the documented API
/// for shaped vibrancy. A SwiftUI `.clipShape` can't do this: the `.behindWindow` backdrop
/// composites at the window-server level and is rendered around SwiftUI's render-tree clip.
struct VibrancyBackground: NSViewRepresentable {
    var cardStyle: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material     = .underWindowBackground
        v.state        = .active
        applyMask(to: v)
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        applyMask(to: nsView)
    }

    private func applyMask(to v: NSVisualEffectView) {
        v.maskImage = cardStyle ? roundedCardMaskImage(radius: cardCornerRadius) : nil
    }
}

/// Blur + Dracula dark tint — the background for every pane. Detail-pane callers pass
/// `cardStyle: true` so the pane reads as a floating rounded glass card matching the
/// macOS sidebar; the sidebar leaves it false (AppKit styles the sidebar itself).
struct DraculaVibrancyBackground: View {
    var cardStyle: Bool = false

    var body: some View {
        if cardStyle {
            ZStack {
                VibrancyBackground(cardStyle: true)
                Color.draculaBg.opacity(cardTintOpacity)
            }
            // Clip the SwiftUI tint layer too (the blur is clipped by maskImage above).
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            // Glass rim: a thin top-lit highlight stroke around the card edge.
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .strokeBorder(glassRimGradient, lineWidth: 1)
            )
        } else {
            ZStack {
                VibrancyBackground()
                Color.draculaBg.opacity(draculaTintOpacity)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - Rounded card helpers

/// Top-lit translucent white gradient used as the glassy rim stroke on cards.
let glassRimGradient = LinearGradient(
    colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
    startPoint: .top, endPoint: .bottom)

/// A resizable mask image with all four corners rounded, for clipping a `.behindWindow`
/// NSVisualEffectView to a floating card. Opaque where the material should show.
func roundedCardMaskImage(radius: CGFloat) -> NSImage {
    let r = max(1, radius)
    let size = NSSize(width: r * 2 + 1, height: r * 2 + 1)
    let image = NSImage(size: size, flipped: false) { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        NSColor.black.setFill()
        path.fill()
        return true
    }
    image.capInsets    = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
    image.resizingMode = .stretch
    return image
}

/// Style a detail-pane NSVisualEffectView as a floating rounded card: `maskImage` clips the
/// behind-window blur, and the layer's `cornerRadius`/`masksToBounds` clip the normal
/// subviews layered on top (the tint and the terminal canvas).
func roundCardCorners(of fx: NSVisualEffectView) {
    fx.maskImage = roundedCardMaskImage(radius: cardCornerRadius)
    fx.wantsLayer = true
    guard let layer = fx.layer else { return }
    layer.cornerRadius  = cardCornerRadius
    layer.cornerCurve   = .continuous
    layer.masksToBounds = true
    // Glass rim to match the SwiftUI card overlay.
    layer.borderWidth = 1
    layer.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
}
