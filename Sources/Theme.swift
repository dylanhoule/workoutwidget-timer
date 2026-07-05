import SwiftUI

// MARK: - Palette
// Committed dark "energetic" look — deliberately not system-adaptive.

extension Color {
    static let bgTop     = Color(red: 0.095, green: 0.090, blue: 0.125)
    static let bgBottom  = Color(red: 0.047, green: 0.047, blue: 0.066)
    static let cardFill  = Color.white.opacity(0.06)
    static let cardEdge  = Color.white.opacity(0.10)
    static let fieldFill = Color.white.opacity(0.08)

    static let accentOrange = Color(red: 1.00, green: 0.42, blue: 0.17)  // #FF6B2C
    static let accentPink   = Color(red: 1.00, green: 0.18, blue: 0.47)  // #FF2D78
    static let glow         = Color(red: 1.00, green: 0.31, blue: 0.37)  // #FF4E5E

    static let textPrimary   = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let textSecondary = Color(red: 0.63, green: 0.63, blue: 0.68)
    static let textTertiary  = Color(red: 0.43, green: 0.43, blue: 0.47)
}

extension LinearGradient {
    static let energy = LinearGradient(colors: [.accentOrange, .accentPink],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension AngularGradient {
    /// Orange → pink → orange so the ring wraps seamlessly at 12 o'clock.
    static let energyRing = AngularGradient(colors: [.accentOrange, .accentPink, .accentOrange],
                                            center: .center)
}

// MARK: - Background

struct ThemeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.bgTop, .bgBottom], startPoint: .top, endPoint: .bottom)
            // Faint warmth behind the ring area.
            RadialGradient(colors: [Color.accentOrange.opacity(0.12), .clear],
                           center: UnitPoint(x: 0.5, y: 0.16),
                           startRadius: 4, endRadius: 210)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Small components

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundColor(.textTertiary)
    }
}

extension View {
    /// Rounded translucent card container.
    func card(padding: CGFloat = 10) -> some View {
        self.padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.cardEdge, lineWidth: 1))
            )
    }

    /// Dark rounded input treatment for TextFields.
    func darkField() -> some View {
        self.textFieldStyle(.plain)
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.textPrimary)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.fieldFill))
    }
}

/// − / field / + reps input; replaces the native Stepper for visual consistency.
struct RepsControl: View {
    @Binding var reps: Int

    var body: some View {
        HStack(spacing: 4) {
            Button { reps = max(0, reps - 1) } label: { Image(systemName: "minus") }
                .buttonStyle(QuietIconButtonStyle(size: 22))
            TextField("", value: $reps, format: .number)
                .darkField()
                .multilineTextAlignment(.center)
                .frame(width: 34)
            Button { reps = min(999, reps + 1) } label: { Image(systemName: "plus") }
                .buttonStyle(QuietIconButtonStyle(size: 22))
        }
    }
}

// MARK: - Button styles
// ButtonStyle can't hold @State, so each makeBody returns an inner view that
// owns the hover flag.

struct EnergyPrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, compact: compact)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.vertical, compact ? 5 : 9)
                .padding(.horizontal, compact ? 12 : 16)
                .background(Capsule().fill(LinearGradient.energy))
                .brightness(hovering && isEnabled ? 0.10 : 0)
                .shadow(color: .glow.opacity(hovering ? 0.55 : 0.35),
                        radius: hovering ? 12 : 7, y: 2)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.textPrimary)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

struct QuietIconButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, size: size)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(hovering ? .textPrimary : .textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

// MARK: - Progress ring

enum RingMode: Equatable { case idle, running, paused }

struct ProgressRing<Content: View>: View {
    let progress: Double
    let mode: RingMode
    private let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(progress: Double, mode: RingMode, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.mode = mode
        self.content = content()
    }

    private var clamped: CGFloat { CGFloat(min(1, max(0, progress))) }
    private var glowOpacity: Double { mode == .running ? 0.55 : 0 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 10)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AngularGradient.energyRing,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: .glow.opacity(glowOpacity), radius: 10)
                .shadow(color: .glow.opacity(glowOpacity * 0.45), radius: 22)
                .opacity(mode == .idle ? 0.25 : (mode == .paused ? 0.5 : 1))
                .saturation(mode == .paused ? 0 : 1)
                // Each 1s tick interpolates linearly across the second → a
                // continuous sweep with no TimelineView and no idle CPU cost.
                .animation(reduceMotion ? nil : .linear(duration: 1), value: clamped)
                .animation(.easeOut(duration: 0.25), value: mode)
            content
        }
        .frame(width: 160, height: 160)
        .padding(6)   // room for the stroke's outer half + glow
    }
}

// MARK: - Round-complete burst

/// One-shot particle burst. Offsets are index-derived (not random) so a parent
/// body re-eval mid-flight can't reshuffle particles.
struct CelebrationBurst: View {
    @State private var fired = false

    var body: some View {
        ZStack {
            ForEach(0..<12, id: \.self) { i in
                let angle = Double(i) / 12 * 2 * .pi + Double((i * 5) % 3) * 0.17
                let radius = 55.0 + Double((i * 29) % 36)
                let size = CGFloat(3 + i % 3)
                Circle()
                    .fill(i % 2 == 0 ? Color.accentOrange : Color.accentPink)
                    .frame(width: size, height: size)
                    .offset(x: fired ? cos(angle) * radius : 0,
                            y: fired ? sin(angle) * radius - 8 : 0)
                    .opacity(fired ? 0 : 1)
                    .scaleEffect(fired ? 0.3 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { fired = true }
        }
    }
}
