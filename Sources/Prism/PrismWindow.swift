import SwiftUI

struct PrismWindow: View {
    @ObservedObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedTheme: Theme
    @State private var covered = false

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
        Dashboard(model: model)
            .overlay {
                Palette.graphite
                    .ignoresSafeArea()
                    .opacity(covered ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
                covered = false
            }
            return
        }

        do {
            if displayedTheme != request.theme {
                withAnimation(.easeIn(duration: 0.12)) { covered = true }
                try await Task.sleep(for: .milliseconds(145))
                try Task.checkCancellation()
                displayedTheme = request.theme
                try await Task.sleep(for: .milliseconds(34))
            }
            try Task.checkCancellation()
            withAnimation(.easeOut(duration: 0.24)) { covered = false }
        } catch {
            // A newer request owns the transition.
        }
    }
}
