import SwiftUI
import UIKit

/// The IsoTrack colour identity, shared by the app and the widget: flat,
/// muted colours on an ink-navy canvas. No gradients anywhere.
extension Color {
    /// A colour that resolves differently in light and dark appearance.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }

    /// The single accent: deep iris in light, soft periwinkle in dark. Used
    /// for progress, the primary action, and anything "done".
    static let brand = Color(light: 0x4651B8, dark: 0x97A1F5)
    /// Text and glyphs that sit on top of a `brand` fill.
    static let onBrand = Color(light: 0xFFFFFF, dark: 0x0D0F17)
    static let good = Color.brand

    /// Warm sand for things that need attention.
    static let warn = Color(light: 0x96621A, dark: 0xE0B878)
    /// Dusty rose for appointments and reference lines.
    static let info = Color(light: 0xA5506A, dark: 0xDD9BAE)

    /// Ink-navy canvas and surfaces: dark, but never neutral grey.
    static let appBackground = Color(light: 0xE6E6EC, dark: 0x0C0E15)
    static let surface = Color(light: 0xF2F2F6, dark: 0x151824)
    static let surfaceRaised = Color(light: 0xDADAE3, dark: 0x202434)
    static let hairline = Color(light: 0x0C0E15, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.07)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The progress ring used on the Today screen and in the widget: a flat
/// accent arc on a quiet track, with an optional reference tick.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat
    /// Position (0...1) of a reference tick drawn on the track.
    var marker: Double? = nil
    var track: Color = .surfaceRaised

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth))

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.brand, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let marker, marker > 0, marker < 1 {
                MarkerTick(position: marker, lineWidth: lineWidth)
            }
        }
        .padding(lineWidth / 2)
    }

    /// A short tick across the ring at `position`.
    private struct MarkerTick: View {
        let position: Double
        let lineWidth: CGFloat

        var body: some View {
            GeometryReader { proxy in
                let radius = min(proxy.size.width, proxy.size.height) / 2
                let angle = Angle.degrees(position * 360 - 90)
                Capsule()
                    .fill(Color.info)
                    .frame(width: 3, height: lineWidth + 6)
                    .rotationEffect(angle + .degrees(90))
                    .position(
                        x: proxy.size.width / 2 + radius * CGFloat(cos(angle.radians)),
                        y: proxy.size.height / 2 + radius * CGFloat(sin(angle.radians))
                    )
            }
        }
    }
}
