import SwiftUI

enum Palette {
    static let brass = Color(red: 0.82, green: 0.70, blue: 0.47)
    static let mutedBrass = Color(red: 0.69, green: 0.60, blue: 0.43)
    static let graphite = Color(white: 0.16)
    static let ink = Color(white: 0.065)

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? brass : Color(red: 0.08, green: 0.34, blue: 0.49)
    }
}

struct GlassSurface: View {
    let radius: CGFloat
    let intensity: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: scheme == .dark ? min(radius, 11) : radius, style: .continuous)
        if scheme == .dark {
            shape.fill(LinearGradient(colors: [Color(white: 0.13 + intensity * 0.12),
                                               Color(white: 0.087 + intensity * 0.07)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    shape.strokeBorder(.white.opacity(0.095 + intensity * 0.10), lineWidth: 1)
                }
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay { shape.fill(.white.opacity(intensity * 0.53)) }
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.84), .white.opacity(0.35)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
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
                             [Palette.brass, Palette.mutedBrass] :
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(colors: dark ? [Palette.graphite, Palette.ink] :
                                     [Color(red: 0.13, green: 0.31, blue: 0.52), .indigo.opacity(0.91)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(.white.opacity(dark ? 0.15 : 0.48), lineWidth: 1)
            RoundedRectangle(cornerRadius: size * 0.087, style: .continuous)
                .fill(LinearGradient(colors: dark ? [Palette.brass, Palette.mutedBrass.opacity(0.25)] :
                                     [.white, .cyan.opacity(0.64), .indigo.opacity(0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.44, height: size * 0.44)
                .rotationEffect(.degrees(45)).offset(x: size * 0.047, y: size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
                .strokeBorder(.white.opacity(0.77), lineWidth: 1)
                .frame(width: size * 0.36, height: size * 0.36)
                .rotationEffect(.degrees(45)).offset(x: -size * 0.095)
        }
        .frame(width: size, height: size)
        .shadow(color: (dark ? Color.black : .indigo).opacity(0.25), radius: 11, y: 4)
        .accessibilityHidden(true)
    }
}

struct Aurora: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            lightAurora
            LinearGradient(stops: [.init(color: Palette.graphite, location: 0),
                                   .init(color: Color(white: 0.105), location: 0.49),
                                   .init(color: Palette.ink, location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(scheme == .dark ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: scheme)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var lightAurora: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion || scheme == .dark)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.16
            ZStack {
                Color(red: 0.924, green: 0.945, blue: 0.975)
                RadialGradient(colors: [.cyan.opacity(0.24), .clear],
                               center: UnitPoint(x: 0.66 + 0.13 * sin(t), y: 0.14 + 0.07 * cos(t)),
                               startRadius: 20, endRadius: 365)
                RadialGradient(colors: [.indigo.opacity(0.19), .clear],
                               center: UnitPoint(x: 0.27 + 0.10 * cos(t * 0.73), y: 0.87 + 0.08 * sin(t)),
                               startRadius: 25, endRadius: 415)
                RadialGradient(colors: [.purple.opacity(0.13), .clear],
                               center: UnitPoint(x: 0.97, y: 0.42 + 0.12 * cos(t * 0.65)),
                               startRadius: 15, endRadius: 320)
            }
        }
    }
}

struct HeroGlass: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let radius = CGFloat(21)
    var body: some View {
        Group {
            if scheme == .dark {
                let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
                shape.fill(LinearGradient(colors: [Palette.graphite, Palette.ink],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { GraphitePrism().clipShape(shape) }
                    .overlay { shape.strokeBorder(.white.opacity(0.15), lineWidth: 1) }
            } else {
                lightHero
            }
        }
        .accessibilityHidden(true)
    }

    private var lightHero: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * 0.26
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            GlassSurface(radius: radius, intensity: 0.41)
                .overlay {
                    shape.fill(RadialGradient(colors: [.cyan.opacity(0.27), .clear],
                                              center: UnitPoint(x: 0.80 + 0.12 * sin(t), y: 0.20 + 0.11 * cos(t)),
                                              startRadius: 4, endRadius: 241))
                }
                .overlay {
                    shape.fill(RadialGradient(colors: [.indigo.opacity(0.16), .clear],
                                              center: UnitPoint(x: 0.40 + 0.1 * cos(t), y: 1.1),
                                              startRadius: 4, endRadius: 220))
                }
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.60), .white.opacity(0.08)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.07), radius: 15, y: 7)
        }
    }
}

private struct GraphitePrism: View {
    var body: some View {
        Canvas { context, size in
            let width = min(size.width * 0.60, size.height * 2.8)
            let origin = size.width - width
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin + width * x, y: size.height * y)
            }
            let peak = point(0.60, -0.36)
            let ridge = point(0.51, 0.67)
            let left = point(0.04, 0.77)
            let right = point(1.06, 0.61)
            let base = point(0.58, 1.45)

            func face(_ vertices: [CGPoint], _ highlight: Double, _ shadow: Double) {
                let path = Path { path in
                    path.addLines(vertices)
                    path.closeSubpath()
                }
                context.fill(path, with: .linearGradient(Gradient(colors: [Color(white: highlight), Color(white: shadow)]),
                                                         startPoint: vertices[0], endPoint: vertices[2]))
                context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 0.75)
            }

            face([peak, ridge, left], 0.38, 0.095)
            face([peak, ridge, right], 0.20, 0.045)
            face([left, ridge, base], 0.18, 0.075)
            face([ridge, right, base], 0.10, 0.035)
        }
    }
}
