import AppKit
import Foundation
import PrismCore
import SwiftUI

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct Confirmation: Identifiable {
    enum Operation { case activate, remove }
    let operation: Operation
    let profile: Profile
    var id: String { profile.id }
}

struct Notice: Identifiable {
    let id = UUID()
    let text: String
    let error: Bool
}

struct LimitDisplay {
    var limits: UsageLimits?
    var error: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var active: AccountIdentity?
    @Published var unsupported = false
    @Published var operation: String?
    @Published var canCancel = false
    @Published var confirmation: Confirmation?
    @Published var notice: Notice?
    @Published var usage: [String: LimitDisplay] = [:]
    @Published var loadingUsage: Set<String> = []
    @Published var theme: Theme {
        didSet { if !preview { UserDefaults.standard.set(theme.rawValue, forKey: "appearance") } }
    }

    let preview: Bool
    let store: AccountStore?
    let home: URL
    private var task: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var lastUsageAttempt = Date.distantPast

    init(preview: Bool) {
        self.preview = preview
        theme = preview ? .light : Theme(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        let fs = FileManager.default
        let path = ProcessInfo.processInfo.environment["CODEX_HOME"]
        home = (path.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            ?? fs.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true))
            .standardizedFileURL.resolvingSymlinksInPath()
        if preview {
            store = nil
            let primary = AccountIdentity(workspace: "demo-personal", principal: "demo-1", email: "alex@example.com", name: "Алекс Морозов", plan: "pro")
            let studio = AccountIdentity(workspace: "demo-studio", principal: "demo-2", email: "studio@example.com", name: "Рабочий аккаунт", plan: "team")
            let lab = AccountIdentity(workspace: "demo-lab", principal: "demo-3", email: "labs@example.com", name: "Лаборатория", plan: "plus")
            active = primary
            profiles = [primary, studio, lab].map { Profile(identity: $0) }
            for (index, profile) in profiles.enumerated() {
                usage[profile.id] = LimitDisplay(limits: UsageLimits(
                    fiveHours: UsageWindow(remainingPercent: [78, 33, 91][index], resetsAt: .now.addingTimeInterval(9500)),
                    week: UsageWindow(remainingPercent: [62, 84, 47][index], resetsAt: .now.addingTimeInterval(4 * 86400))))
            }
        } else {
            let appData = fs.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Prism", isDirectory: true)
            store = AccountStore(home: home, root: appData)
        }
    }

    func refresh(forceLimits: Bool = false) async {
        guard let store = store, operation == nil else { return }
        do {
            let old = active?.id
            try await read(store)
            if old != active?.id, let pending = usageTask {
                pending.cancel()
                await pending.value
            }
            refreshUsage(force: forceLimits || old != active?.id)
        }
        catch { show(message(error), error: true) }
    }

    func saveActive() {
        perform("Сохраняю аккаунт…") {
            guard let store = self.store else {
                self.show("Демонстрационный аккаунт уже сохранён.")
                return
            }
            _ = try await store.importCurrent()
            try await self.read(store)
            self.show("Текущий вход сохранён в Связке ключей.")
        }
    }

    func addAccount() {
        perform("Ожидаю входа в браузере…", cancellable: true) {
            guard let store = self.store else {
                try await Task.sleep(nanoseconds: 450_000_000)
                let example = AccountIdentity(workspace: UUID().uuidString, principal: "demo", email: "guest@example.com", name: "Гостевой аккаунт", plan: "free")
                self.profiles.append(Profile(identity: example))
                self.show("Демонстрационный аккаунт добавлен.")
                return
            }
            let runtime = try CodexRuntime.locate()
            let credential = try await runtime.signIn { url in
                await MainActor.run { NSWorkspace.shared.open(url) }
            }
            try Task.checkCancellation()
            _ = try await store.save(credential)
            try await self.read(store)
            self.show("Аккаунт добавлен. Его можно выбрать в списке.")
        }
    }

    func cancel() { if canCancel { task?.cancel() } }

    func confirm(_ action: Confirmation) {
        switch action.operation {
        case .remove:
            perform("Удаляю сохранённую сессию…") {
                if let store = self.store {
                    try await store.remove(action.profile.id)
                    try await self.read(store)
                } else {
                    self.profiles.removeAll { $0.id == action.profile.id }
                }
                self.show("Сохранённая сессия удалена.")
            }
        case .activate:
            perform("Проверяю режим хранения Codex…") {
                guard let store = self.store else {
                    try await Task.sleep(nanoseconds: 520_000_000)
                    self.active = action.profile.identity
                    self.show("Аккаунт переключён в режиме демонстрации.")
                    return
                }
                let runtime = try CodexRuntime.locate()
                let home = self.home
                try await store.validateTarget(action.profile.id)
                try await runtime.checkStorage(home: home)
                let desktop = Desktop(home: home)
                let wasRunning = desktop.isRunning
                self.operation = "Ожидаю завершения Codex…"
                try await desktop.close()
                do {
                    try await desktop.waitForCLI()
                    self.operation = "Проверяю выбранный аккаунт…"
                    _ = try await store.activate(action.profile.id) { identity in
                        try await runtime.verify(identity, home: home)
                    }
                } catch {
                    if wasRunning { try? await desktop.open() }
                    throw error
                }
                try await self.read(store)
                do {
                    try await desktop.open()
                    self.show("Аккаунт переключён. Codex открыт.")
                } catch {
                    self.show("Аккаунт переключён. Открой Codex вручную.")
                }
            }
        }
    }

    private func read(_ store: AccountStore) async throws {
        let snapshot = try await store.snapshot()
        profiles = snapshot.profiles
        active = snapshot.active
        unsupported = snapshot.activeUnsupported
    }

    private func perform(_ text: String, cancellable: Bool = false, body: @escaping () async throws -> Void) {
        guard operation == nil else { return }
        operation = text
        canCancel = cancellable
        let pending = usageTask
        pending?.cancel()
        task = Task {
            await pending?.value
            var finished = false
            do {
                try Task.checkCancellation()
                try await body()
                finished = true
            }
            catch is CancellationError { show("Вход отменён.") }
            catch { show(message(error), error: true) }
            operation = nil
            canCancel = false
            task = nil
            refreshUsage(force: finished)
        }
    }

    private func refreshUsage(force: Bool) {
        guard let store = store, operation == nil, usageTask == nil,
              force || Date.now.timeIntervalSince(lastUsageAttempt) >= 90 else { return }
        let activeIDs = active.map { [$0.id] } ?? []
        let ids = activeIDs + profiles.map(\.id).filter { !activeIDs.contains($0) }
        let currentIDs = Set(ids)
        usage = usage.filter { currentIDs.contains($0.key) }
        guard !ids.isEmpty else { return }
        lastUsageAttempt = .now
        loadingUsage = currentIDs
        usageTask = Task {
            defer { loadingUsage = []; usageTask = nil }
            guard let runtime = try? CodexRuntime.locate() else {
                for id in ids { usageFailed(id, .runtimeMissing) }
                return
            }
            await withTaskGroup(of: (String, Result<UsageLimits, PrismError>).self) { group in
                var remaining = ids.makeIterator()
                func enqueue() {
                    guard !Task.isCancelled, let id = remaining.next() else { return }
                    group.addTask {
                        do {
                            let credential = try await store.credentialForUsage(id)
                            return (id, .success(try await runtime.usage(for: credential)))
                        } catch {
                            return (id, .failure(error as? PrismError ?? .runtimeFailed))
                        }
                    }
                }
                for _ in 0..<min(ids.count, 3) { enqueue() }
                for await (id, result) in group {
                    guard !Task.isCancelled else { group.cancelAll(); break }
                    await MainActor.run { finishUsage(id, result) }
                    enqueue()
                }
            }
        }
    }

    private func finishUsage(_ id: String, _ result: Result<UsageLimits, PrismError>) {
        switch result {
        case .success(let limits): usage[id] = LimitDisplay(limits: limits)
        case .failure(let error): usageFailed(id, error)
        }
        loadingUsage.remove(id)
    }

    private func usageFailed(_ id: String, _ error: PrismError) {
        usage[id] = LimitDisplay(limits: usage[id]?.limits, error: error.localizedDescription)
    }

    private func message(_ error: Error) -> String {
        (error as? PrismError)?.errorDescription ?? "Не удалось завершить операцию с локальным хранилищем."
    }

    private func show(_ text: String, error: Bool = false) {
        toastTask?.cancel()
        let shown = Notice(text: text, error: error)
        notice = shown
        toastTask = Task {
            do { try await Task.sleep(nanoseconds: error ? 11_000_000_000 : 4_800_000_000) }
            catch { return }
            if notice?.id == shown.id { notice = nil }
        }
    }
}

@MainActor
private struct Desktop {
    let home: URL
    private let bundleID = "com.openai.codex"
    private var instances: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
    }
    var isRunning: Bool { !instances.isEmpty }

    func close() async throws {
        for app in instances where !app.terminate() && !app.isTerminated { throw PrismError.desktopBusy }
        let deadline = ProcessInfo.processInfo.systemUptime + 25
        while isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw PrismError.desktopBusy }
            try await Task.sleep(nanoseconds: 140_000_000)
        }
    }

    func waitForCLI() async throws {
        for _ in 0..<12 {
            guard !isRunning else { throw PrismError.desktopBusy }
            if try !Self.cliRunning() { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw PrismError.desktopBusy
    }

    func open() async throws {
        let workspace = NSWorkspace.shared
        let paths = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID)
                ?? paths.map({ URL(fileURLWithPath: $0) }).first(where: { Bundle(url: $0)?.bundleIdentifier == bundleID })
        else { throw PrismError.desktopMissing }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.environment = ["CODEX_HOME": home.path]
        _ = try await workspace.openApplication(at: url, configuration: configuration)
    }

    nonisolated private static func cliRunning() throws -> Bool {
        let proc = Process(), output = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "comm="]
        proc.standardOutput = output
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() }
        catch { throw PrismError.desktopBusy }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0, let text = String(data: data, encoding: .utf8)
        else { throw PrismError.desktopBusy }
        return text.split(whereSeparator: \.isNewline).contains { line in
            let executable = (line.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent.lowercased()
            return executable == "codex" || executable == "codex-cli" || executable == "codexcli"
        }
    }
}
