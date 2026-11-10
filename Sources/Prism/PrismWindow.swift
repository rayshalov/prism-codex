import AppKit
import SwiftUI

struct PrismWindow: View {
    @ObservedObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var systemScheme: ColorScheme
    @State private var displayedScheme: ColorScheme
    @State private var transitioning = false

    private struct ThemeRequest: Equatable {
        let scheme: ColorScheme
        let reduceMotion: Bool
    }

    @MainActor
    init(model: AppModel) {
        self.model = model
        let systemScheme = Self.scheme(for: NSApplication.shared.effectiveAppearance)
        _systemScheme = State(initialValue: systemScheme)
        _displayedScheme = State(initialValue: model.theme.scheme ?? systemScheme)
    }

    var body: some View {
        let request = ThemeRequest(scheme: model.theme.scheme ?? systemScheme, reduceMotion: reduceMotion)
        Dashboard(model: model, themeInMotion: transitioning && !reduceMotion)
            .preferredColorScheme(displayedScheme)
            .onReceive(NSApplication.shared.publisher(for: \.effectiveAppearance)
                .map(Self.scheme(for:)).removeDuplicates()) { scheme in
                if systemScheme != scheme { systemScheme = scheme }
            }
            .task(id: request) { await apply(request) }
    }

    private static func scheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    @MainActor
    private func apply(_ request: ThemeRequest) async {
        guard !Task.isCancelled else { return }
        if request.reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedScheme = request.scheme
                transitioning = false
            }
            return
        }

        do {
            if displayedScheme != request.scheme {
                withAnimation(.easeInOut(duration: 0.18)) { transitioning = true }
                try await Task.sleep(for: .milliseconds(195))
                try Task.checkCancellation()
                displayedScheme = request.scheme
                try await Task.sleep(for: .milliseconds(34))
            }
            try Task.checkCancellation()
            withAnimation(.easeOut(duration: 0.32)) { transitioning = false }
        } catch {
            // A newer request owns the transition.
        }
    }
}
