import SwiftUI

/// The app's motion vocabulary. Everything here stands down when Reduce
/// Motion is on.
enum Motion {
    /// Settles with a little life; the default for state changes.
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Overshoots and settles; for things that should feel like a pop.
    static let pop = Animation.spring(response: 0.38, dampingFraction: 0.58)
    /// Long, soft settle for rings and bars filling.
    static let fill = Animation.spring(response: 1.0, dampingFraction: 0.82)
    /// Delay between neighbouring items in a staggered entrance.
    static let stagger = 0.065
}

// MARK: - Entrances

/// Rises into place — fading, sharpening and settling — once, the first time
/// it appears. `index` staggers neighbours.
struct RiseIn: ViewModifier {
    let index: Int
    var distance: CGFloat = 28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 8)
            .scaleEffect(shown ? 1 : 0.95, anchor: .top)
            .offset(y: shown ? 0 : distance)
            .onAppear {
                guard !shown else { return }
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(.spring(response: 0.62, dampingFraction: 0.78).delay(Double(index) * Motion.stagger)) {
                    shown = true
                }
            }
    }
}

extension View {
    func riseIn(_ index: Int = 0, distance: CGFloat = 28) -> some View {
        modifier(RiseIn(index: index, distance: distance))
    }

    /// Cards ease back — smaller, dimmer, softer — as they slide out of a
    /// scroll view, and come forward again as they return.
    func recedesAtScrollEdges() -> some View {
        // Only the last sliver of a card is affected, so text stays readable
        // right up until the card is nearly gone.
        scrollTransition(.interactive.threshold(.visible(0.12))) { content, phase in
            content
                .scaleEffect(1 - 0.06 * abs(phase.value))
                .opacity(1 - 0.5 * abs(phase.value))
                .blur(radius: 2 * abs(phase.value))
        }
    }
}

/// A column of cards. Each one makes a staggered entrance and recedes at the
/// scroll edges.
struct CardStack<Content: View>: View {
    /// Offsets the stagger so a second column follows the first.
    var startIndex = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    subview
                        .recedesAtScrollEdges()
                        .riseIn(startIndex + index)
                }
            }
        }
    }
}

// MARK: - Numbers

/// A number that counts smoothly to its new value instead of jumping.
struct RollingNumber: View, Animatable {
    var value: Double
    var format: (Double) -> String = { CourseSnapshot.whole($0) }

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
            .monospacedDigit()
    }
}

// MARK: - Confirmation

/// The "done" mark: a disc pops in, a ripple rings out, and the tick draws
/// itself.
struct CheckBurst: View {
    var size: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false
    @State private var rippled = false
    @State private var ticked = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.brand, lineWidth: 2)
                .scaleEffect(rippled ? 2.1 : 1)
                .opacity(rippled ? 0 : 0.7)
            Circle()
                .fill(Color.brand)
                .scaleEffect(popped ? 1 : 0.3)
                .opacity(popped ? 1 : 0)
            TickShape()
                .trim(from: 0, to: ticked ? 1 : 0)
                .stroke(Color.onBrand, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.40, height: size * 0.30)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                popped = true
                rippled = true
                ticked = true
                return
            }
            withAnimation(Motion.pop) { popped = true }
            withAnimation(.easeOut(duration: 0.8).delay(0.08)) { rippled = true }
            withAnimation(.easeOut(duration: 0.32).delay(0.2)) { ticked = true }
        }
    }
}

/// A check mark drawn as a stroke, so it can be trimmed to draw itself.
struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A round check box. Turning on, the disc pops in, a ripple rings out and
/// the tick draws itself; turning off, it empties back to an outline.
struct CheckCircle: View {
    var isOn: Bool
    var size: CGFloat = 30

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ripple = 0

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.brand, lineWidth: 2)
                .keyframeAnimator(initialValue: Ripple(), trigger: ripple) { view, value in
                    view.scaleEffect(value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1, duration: 0.01)
                        CubicKeyframe(2.2, duration: 0.6)
                    }
                    KeyframeTrack(\.opacity) {
                        CubicKeyframe(0.7, duration: 0.01)
                        CubicKeyframe(0, duration: 0.6)
                    }
                }
            Circle()
                .strokeBorder(Color.secondary.opacity(0.55), lineWidth: 2)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(Color.brand)
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
                .animation(reduceMotion ? nil : Motion.pop, value: isOn)
            TickShape()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(Color.onBrand, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.40, height: size * 0.30)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(isOn ? 0.12 : 0), value: isOn)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: isOn) { _, on in
            if on, !reduceMotion { ripple += 1 }
        }
    }

    private struct Ripple {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}

// MARK: - Small flourishes

/// A quick swell-and-settle whenever `trigger` changes.
struct PulseOnChange<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    var amount: CGFloat = 1.06

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(amount, duration: 0.16, spring: .snappy)
                SpringKeyframe(1, duration: 0.5, spring: .bouncy)
            }
        }
    }
}

extension View {
    func pulse<Trigger: Equatable>(on trigger: Trigger, amount: CGFloat = 1.06) -> some View {
        modifier(PulseOnChange(trigger: trigger, amount: amount))
    }

    /// A slow, gentle bob for hero artwork.
    func floating() -> some View {
        modifier(Floating())
    }
}

private struct Floating: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: up ? -7 : 5)
            .rotationEffect(.degrees(up ? -3 : 2))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                    up = true
                }
            }
    }
}
