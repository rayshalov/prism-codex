import SwiftUI

enum Palette {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.47, green: 0.87, blue: 0.93) : Color(red: 0.08, green: 0.34, blue: 0.49)
    }
}

struct GlassSurface: View {
    let radius: CGFloat
    let intensity: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(.ultraThinMaterial)
            .overlay {
                shape.fill(.white.opacity(scheme == .dark ? intensity * 0.10 : intensity * 0.53))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.29 : 0.84),
                                                           .white.opacity(scheme == .dark ? 0.06 : 0.35)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
    }
}

struct GlassButton: ButtonStyle {
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(prominent ? (scheme == .dark ? Color.black : .white) : .primary)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: scheme == .dark ?
                             [Color(red: 0.68, green: 0.94, blue: 0.95), Color(red: 0.36, green: 0.72, blue: 0.91)] :
                             [Color(red: 0.17, green: 0.39, blue: 0.60), Color(red: 0.14, green: 0.29, blue: 0.52)],
                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.27), lineWidth: 1) }
                } else {
                    GlassSurface(radius: 12, intensity: 0.34)
                }
            }
            .opacity(enabled ? 1 : 0.46)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.23, dampingFraction: 0.69), value: configuration.isPressed)
    }
}

struct PrismMark: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.31, blue: 0.52), .indigo.opacity(0.91)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(.white.opacity(0.48), lineWidth: 1)
            RoundedRectangle(cornerRadius: size * 0.087, style: .continuous)
                .fill(LinearGradient(colors: [.white, .cyan.opacity(0.64), .indigo.opacity(0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.44, height: size * 0.44)
                .rotationEffect(.degrees(45)).offset(x: size * 0.047, y: size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
                .strokeBorder(.white.opacity(0.77), lineWidth: 1)
                .frame(width: size * 0.36, height: size * 0.36)
                .rotationEffect(.degrees(45)).offset(x: -size * 0.095)
        }
        .frame(width: size, height: size)
        .shadow(color: .indigo.opacity(0.25), radius: 11, y: 4)
        .accessibilityHidden(true)
    }
}

struct Aurora: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.16
            ZStack {
                (scheme == .dark ? Color(red: 0.050, green: 0.071, blue: 0.12)
                                 : Color(red: 0.924, green: 0.945, blue: 0.975))
                RadialGradient(colors: [.cyan.opacity(scheme == .dark ? 0.27 : 0.24), .clear],
                               center: UnitPoint(x: 0.66 + 0.13 * sin(t), y: 0.14 + 0.07 * cos(t)),
                               startRadius: 20, endRadius: 365)
                RadialGradient(colors: [.indigo.opacity(scheme == .dark ? 0.46 : 0.19), .clear],
                               center: UnitPoint(x: 0.27 + 0.10 * cos(t * 0.73), y: 0.87 + 0.08 * sin(t)),
                               startRadius: 25, endRadius: 415)
                RadialGradient(colors: [.purple.opacity(scheme == .dark ? 0.21 : 0.13), .clear],
                               center: UnitPoint(x: 0.97, y: 0.42 + 0.12 * cos(t * 0.65)),
                               startRadius: 15, endRadius: 320)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct HeroGlass: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let radius = CGFloat(21)
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.26
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            GlassSurface(radius: radius, intensity: 0.41)
                .overlay {
                    shape.fill(RadialGradient(colors: [.cyan.opacity(scheme == .dark ? 0.34 : 0.27), .clear],
                                              center: UnitPoint(x: 0.80 + 0.12 * sin(t), y: 0.20 + 0.11 * cos(t)),
                                              startRadius: 4, endRadius: 241))
                }
                .overlay {
                    shape.fill(RadialGradient(colors: [.indigo.opacity(scheme == .dark ? 0.28 : 0.16), .clear],
                                              center: UnitPoint(x: 0.40 + 0.1 * cos(t), y: 1.1),
                                              startRadius: 4, endRadius: 220))
                }
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.60), .white.opacity(0.08)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.16 : 0.07), radius: 15, y: 7)
        }
        .accessibilityHidden(true)
    }
}
