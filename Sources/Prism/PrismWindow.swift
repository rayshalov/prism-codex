import SwiftUI

struct PrismWindow: View {
    @ObservedObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedTheme: Theme
    @State private var transitioning = false

    private struct ThemeRequest: Equatable {
        let theme: Theme
        let reduceMotion: Bool
    }

    init(model: AppModel) {
        self.model = model
        _displayedTheme = State(initialValue: model.theme)
    }

    var body: some View {
        let request = ThemeRequest(theme: model.theme, reduceMotion: reduceMotion)
        let inMotion = transitioning && !reduceMotion
        ZStack {
            Palette.graphite.ignoresSafeArea().accessibilityHidden(true)
            Dashboard(model: model)
                .blur(radius: inMotion ? 14 : 0)
                .offset(y: inMotion ? 10 : 0)
                .opacity(inMotion ? 0.28 : 1)
        }
        .preferredColorScheme(displayedTheme.scheme)
        .task(id: request) { await apply(request) }
    }

    @MainActor
    private func apply(_ request: ThemeRequest) async {
        guard !Task.isCancelled else { return }
        if request.reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                displayedTheme = request.theme
                transitioning = false
            }
            return
        }

        do {
            if displayedTheme != request.theme {
                withAnimation(.easeInOut(duration: 0.18)) { transitioning = true }
                try await Task.sleep(for: .milliseconds(195))
                try Task.checkCancellation()
                displayedTheme = request.theme
                try await Task.sleep(for: .milliseconds(34))
            }
            try Task.checkCancellation()
            withAnimation(.easeOut(duration: 0.32)) { transitioning = false }
        } catch {
            // A newer request owns the transition.
        }
    }
}
