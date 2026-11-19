import SwiftUI

/// A one-shot particle burst drawn in a Canvas. Fires whenever `trigger`
/// changes; `big` throws more pieces for milestones.
struct ConfettiView: View {
    let trigger: Int
    let big: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [Particle] = []
    @State private var start: Date?

    private static let duration: TimeInterval = 2.4
    private static let colors: [Color] = [.brand, .info, .warn]

    private struct Particle {
        var x: CGFloat          // launch position, 0...1 of width
        var velocity: CGVector  // points per second
        var size: CGFloat
        var spin: Double
        var color: Color
        var isRound: Bool
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, size in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t < Self.duration else { return }
                let fade = max(0, 1 - max(0, t - 1.5) / (Self.duration - 1.5))

                for particle in particles {
                    let x = particle.x * size.width + particle.velocity.dx * t
                    let y = size.height * 0.34 + particle.velocity.dy * t + 520 * t * t
                    var piece = context
                    piece.opacity = fade
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(particle.spin * t))
                    let rect = CGRect(x: -particle.size / 2, y: -particle.size / 2,
                                      width: particle.size, height: particle.size * (particle.isRound ? 1 : 0.5))
                    let path = particle.isRound ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    piece.fill(path, with: .color(particle.color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        guard !reduceMotion else { return }
        let count = big ? 150 : 46
        particles = (0..<count).map { _ in
            Particle(
                x: .random(in: 0.3...0.7),
                velocity: CGVector(dx: .random(in: -260...260), dy: .random(in: -520 ... -160)),
                size: .random(in: 6...11),
                spin: .random(in: -9...9),
                color: Self.colors.randomElement() ?? .brand,
                isRound: Bool.random()
            )
        }
        let started = Date()
        start = started
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) {
            // Stop the timeline unless a newer burst has taken over.
            if start == started { start = nil }
        }
    }
}

/// A short banner that drops in when a milestone is crossed.
struct CelebrationBanner: View {
    let celebration: AppStore.Celebration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.onBrand)
                .frame(width: 40, height: 40)
                .background(Color.brand, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(celebration.title)
                    .font(.display(.headline))
                Text(celebration.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .frame(maxWidth: 380)
        .modifier(GlassCapsule())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// Liquid Glass where it exists, a material capsule before iOS 26.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
        }
    }
}
