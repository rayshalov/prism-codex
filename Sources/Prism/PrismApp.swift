import AppKit
import SwiftUI

@main
struct PrismApp: App {
    @StateObject private var model = AppModel(preview: CommandLine.arguments.contains("--preview"))

    var body: some Scene {
        WindowGroup("Prism") {
            Dashboard(model: model)
                .frame(minWidth: 790, minHeight: 555)
                .preferredColorScheme(model.theme.scheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 915, height: 625)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Аккаунты") {
                Button("Добавить аккаунт") { model.addAccount() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.operation != nil)
                Button("Сохранить текущий вход") { model.saveActive() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.operation != nil || model.active == nil)
                Button("Обновить") { Task { await model.refresh(forceLimits: true) } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.operation != nil)
            }
        }
    }
}
