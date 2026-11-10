import AppKit
import PrismCore
import SwiftUI

private enum Page: String, CaseIterable {
    case accounts, appearance
    var name: String { self == .accounts ? "Аккаунты" : "Внешний вид" }
    var icon: String { self == .accounts ? "person.crop.rectangle.stack" : "paintpalette" }
}

struct Dashboard: View {
    @ObservedObject var model: AppModel
    let themeInMotion: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.accounts
    @State private var revealed = false
    private let sidebarWidth: CGFloat = 208

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                sidebar
                Group {
                    if page == .accounts { accountsPage }
                    else { appearancePage }
                }
                .transition(.opacity.combined(with: .offset(x: 9)))
            }
            .blur(radius: reduceMotion || revealed ? 0 : 14)
            .opacity(reduceMotion || revealed ? 1 : 0.25)
            .offset(y: reduceMotion || revealed ? 0 : 5)
            .task {
                guard !revealed else { return }
                if reduceMotion {
                    revealed = true
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(70))
                    withAnimation(.easeOut(duration: 0.56)) { revealed = true }
                } catch {}
            }
            if let operation = model.operation {
                statusBanner(operation)
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let notice = model.notice {
                noticeBanner(notice)
                    .padding(24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .blur(radius: themeInMotion ? 14 : 0)
        .offset(y: themeInMotion ? 10 : 0)
        .opacity(themeInMotion ? 0.48 : 1)
        .background(alignment: .leading) { sidebarBackdrop }
        .background { Aurora() }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84), value: page)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.operation != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: model.notice?.id)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .sheet(item: $model.confirmation) { action in confirmationSheet(action) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 11) {
                PrismMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Prism")
                        .font(.system(size: 25, weight: scheme == .dark ? .bold : .semibold,
                                      design: scheme == .dark ? .default : .rounded)).tracking(-0.7)
                    Text("ПРОФИЛИ CODEX").font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.7).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            VStack(alignment: .leading, spacing: 7) {
                Text("ПРОСТРАНСТВО").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.7).foregroundStyle(.secondary).padding(.leading, 10)
                ForEach(Page.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon).frame(width: 19)
                                .foregroundStyle(page == item ? Palette.accent(scheme) : .secondary)
                            Text(item.name).font(.system(size: 13, weight: page == item ? .semibold : .medium))
                            Spacer()
                            if page == item && scheme == .light {
                                Circle().fill(Palette.accent(scheme)).frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 39)
                        .background {
                            if page == item {
                                if scheme == .dark {
                                    Rectangle().fill(.white.opacity(0.055))
                                        .overlay(alignment: .leading) {
                                            Rectangle().fill(Palette.brass).frame(width: 2).padding(.vertical, 9)
                                        }
                                } else {
                                    GlassSurface(radius: 13, intensity: 0.25)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "lock.shield").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.accent(scheme))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.preview ? "Демонстрация" : "Локальное хранение").font(.system(size: 11, weight: .semibold))
                    Text(model.preview ? "Пример аккаунтов" : "Сессии в Связке ключей").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GlassSurface(radius: 14, intensity: 0.11) }
        }
        .padding(.horizontal, 17)
        .padding(.top, 45)
        .padding(.bottom, 21)
        .frame(width: sidebarWidth)
    }

    private var sidebarBackdrop: some View {
        ZStack(alignment: .trailing) {
            Color(red: 0.90, green: 0.91, blue: 0.94).opacity(0.68)
            LinearGradient(colors: [Palette.graphite, Palette.ink], startPoint: .top, endPoint: .bottom)
                .opacity(scheme == .dark ? 1 : 0)
            Rectangle().fill(.white.opacity(scheme == .dark ? 0.09 : 0.22)).frame(width: 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: scheme)
        .frame(width: sidebarWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center) {
                heading("ПРОСТРАНСТВО / АККАУНТЫ", "Аккаунты Codex", "Выбирай, под каким аккаунтом работать.")
                Spacer(minLength: 13)
                Button { Task { await model.refresh(forceLimits: true) } } label: {
                    Group {
                        if model.loadingUsage.isEmpty {
                            Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }.frame(width: 35, height: 35)
                }
                .buttonStyle(GlassButton())
                .help("Обновить аккаунты и лимиты")
                .accessibilityLabel("Обновить аккаунты и лимиты")
                .disabled(model.operation != nil || !model.loadingUsage.isEmpty)
                Button { model.addAccount() } label: {
                    Label("Добавить", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 13).frame(height: 35)
                }
                .buttonStyle(GlassButton(prominent: true))
                .disabled(model.operation != nil)
            }

            activeCard

            HStack(alignment: .center) {
                Text("Сохранённые аккаунты").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(String(model.profiles.count)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background {
                        if scheme == .dark { Capsule().fill(.white.opacity(0.07)) }
                        else { Capsule().fill(.thinMaterial) }
                    }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            if model.profiles.isEmpty { emptyCard }
            else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.profiles) { profile in
                            AccountRow(profile: profile, active: model.active?.id == profile.id,
                                       usage: model.usage[profile.id], loading: model.loadingUsage.contains(profile.id),
                                       disabled: model.operation != nil, select: {
                                model.confirmation = Confirmation(operation: .activate, profile: profile)
                            }, remove: {
                                model.confirmation = Confirmation(operation: .remove, profile: profile)
                            })
                        }
                    }
                    .padding(.bottom, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activeCard: some View {
        let identity = model.active
        let saved = model.profiles.contains { $0.id == identity?.id }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(identity != nil ? (scheme == .dark ? Palette.brass : .teal) : .secondary)
                        .frame(width: 6, height: 6)
                        .shadow(color: .teal.opacity(scheme == .dark ? 0 : 0.62), radius: 5)
                    Text("ТЕКУЩИЙ ВХОД").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.3)
                        .foregroundStyle(Palette.accent(scheme))
                }
                .padding(.vertical, 6).padding(.horizontal, scheme == .dark ? 0 : 9)
                .background {
                    if scheme == .light { Capsule().fill(.ultraThinMaterial) }
                }
                Spacer()
                if let plan = identity?.plan { PlanBadge(plan: plan) }
            }
            HStack(spacing: 13) {
                Avatar(identity: identity, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(identity?.displayName ?? "Вход не обнаружен").font(.system(size: 21, weight: .semibold)).lineLimit(1)
                    Text(identity?.email ?? (model.unsupported ? "Активный вход использует другой режим." : "Войди через Codex или добавь аккаунт в Prism."))
                        .foregroundStyle(.secondary).font(.system(size: 12)).lineLimit(2)
                }
                Spacer(minLength: 6)
                if identity != nil {
                    if saved {
                        Label("В Связке ключей", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    } else {
                        Button { model.saveActive() } label: {
                            Label("Сохранить вход", systemImage: "tray.and.arrow.down")
                                .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 11).frame(height: 32)
                        }
                        .buttonStyle(GlassButton()).disabled(model.operation != nil)
                    }
                }
            }
            if let identity = identity {
                LimitStrip(usage: model.usage[identity.id], loading: model.loadingUsage.contains(identity.id), expanded: true)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 125, alignment: .leading)
        .background { HeroGlass() }
    }

    private var emptyCard: some View {
        HStack(spacing: 13) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 23, weight: .light)).foregroundStyle(Palette.accent(scheme))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text("Здесь будут твои аккаунты").font(.system(size: 14, weight: .semibold))
                Text("Сохрани текущий вход или добавь ещё один через браузер.").font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background { GlassSurface(radius: 17, intensity: 0.20) }
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("ПРОСТРАНСТВО / ОФОРМЛЕНИЕ", "Внешний вид", "Настрой тему приложения.")
            HStack(spacing: 11) {
                ForEach(Theme.allCases) { theme in
                    ThemeTile(theme: theme, selected: model.theme == theme) { model.theme = theme }
                }
            }
            HStack(spacing: 11) {
                Image(systemName: "sparkles").foregroundStyle(Palette.accent(scheme))
                Text("Prism учитывает системную настройку «Уменьшение движения».")
                    .foregroundStyle(.secondary).font(.system(size: 12))
                Spacer()
            }
            .padding(14)
            .background { GlassSurface(radius: 16, intensity: 0.16) }
            Spacer()
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func heading(_ section: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: scheme == .dark ? 8 : 6) {
            Text(section).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.8)
                .foregroundStyle(Palette.accent(scheme))
            if scheme == .dark { Rectangle().fill(Palette.mutedBrass).frame(width: 37, height: 1) }
            Text(title)
                .font(.system(size: scheme == .dark ? 40 : 29, weight: scheme == .dark ? .bold : .semibold,
                              design: scheme == .dark ? .default : .rounded))
                .tracking(scheme == .dark ? -1.7 : -0.8)
            Text(detail).foregroundStyle(.secondary).font(.system(size: 12))
        }
    }

    private func statusBanner(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(title).font(.system(size: 12, weight: .semibold))
            if model.canCancel { Button("Отменить") { model.cancel() }.controlSize(.small) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background { GlassSurface(radius: 15, intensity: 0.67) }
        .shadow(color: .black.opacity(0.14), radius: 9, y: 3)
        .accessibilityElement(children: .combine)
    }

    private func noticeBanner(_ notice: Notice) -> some View {
        HStack(spacing: 9) {
            Image(systemName: notice.error ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(notice.error ? .orange : (scheme == .dark ? Palette.brass : .teal))
            Text(notice.text).font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: 390, alignment: .leading)
        .background { GlassSurface(radius: 15, intensity: 0.75) }
        .shadow(color: .black.opacity(0.14), radius: 9, y: 3)
    }

    private func confirmationSheet(_ action: Confirmation) -> some View {
        let activation = action.operation == .activate
        return VStack(alignment: .leading, spacing: 13) {
            Avatar(identity: action.profile.identity, size: 46)
            Text(activation ? "Переключить аккаунт?" : "Удалить сохранённый вход?")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text(action.profile.identity.email ?? action.profile.identity.displayName)
                .font(.system(size: 13, weight: .semibold))
            Text(activation
                 ? "Prism сохранит текущий вход, закроет Codex и откроет его с выбранным аккаунтом. Перед переключением заверши активные задачи."
                 : "Сессия исчезнет из Prism. В этот аккаунт можно войти снова через браузер.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                Button("Отмена") { model.confirmation = nil }.keyboardShortcut(.cancelAction)
                Button(activation ? "Переключить" : "Удалить") {
                    model.confirmation = nil
                    model.confirm(action)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(activation ? Palette.accent(scheme) : .red)
            }
            .padding(.top, 7)
        }
        .padding(23).frame(width: 410)
    }
}

private struct AccountRow: View {
    let profile: Profile
    let active: Bool
    let usage: LimitDisplay?
    let loading: Bool
    let disabled: Bool
    let select: () -> Void
    let remove: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Avatar(identity: profile.identity, size: 35)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.identity.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let email = profile.identity.email {
                    Text(email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            LimitStrip(usage: usage, loading: loading, expanded: false)
                .layoutPriority(1)
            if let plan = profile.identity.plan { PlanBadge(plan: plan) }
            if active {
                Label("Активен", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent(scheme))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10).frame(height: 29)
            } else {
                Button(action: select) {
                    Label("Выбрать", systemImage: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent(scheme))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9).frame(height: 27)
                }
                .buttonStyle(GlassButton()).disabled(disabled)
                Menu {
                    Button("Удалить сохранённый вход", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(disabled)
                .accessibilityLabel("Действия с аккаунтом")
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7).frame(minHeight: 53)
        .background { GlassSurface(radius: 15, intensity: hovering ? 0.30 : 0.17) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
    }
}

private struct LimitStrip: View {
    let usage: LimitDisplay?
    let loading: Bool
    let expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: expanded ? 10 : 7) {
                LimitMeter(title: "5 ч", window: usage?.limits?.fiveHours, expanded: expanded, weekly: false)
                LimitMeter(title: "Неделя", window: usage?.limits?.week, expanded: expanded, weekly: true)
                if !expanded, let message = usage?.error {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 11))
                        .foregroundStyle(.orange).help(message).accessibilityLabel(message)
                }
            }
            .opacity(usage?.error == nil ? 1 : 0.73)
            if expanded, let error = usage?.error {
                Label(usage?.limits == nil ? error : "Не удалось обновить. Показаны последние полученные данные.",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).help(error)
            } else if expanded && loading && usage == nil {
                Text("Загружаю лимиты…").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LimitMeter: View {
    let title: String
    let window: UsageWindow?
    let expanded: Bool
    let weekly: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percent: String {
        guard let value = window?.remainingPercent else { return "—" }
        return value > 0 && value < 1 ? "<1%" : "\(Int(value.rounded(.down)))%"
    }

    private var reset: String? {
        window?.resetsAt.map { $0.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "ru"))) }
    }

    private var meterColor: Color {
        if let value = window?.remainingPercent, value <= 15 { return .orange }
        if weekly { return scheme == .dark ? Color(white: 0.74) : .indigo }
        return Palette.accent(scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 5 : 4) {
            HStack(spacing: 4) {
                Text(title).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text(percent).foregroundStyle(window == nil ? Color.secondary : meterColor).monospacedDigit().fixedSize(horizontal: true, vertical: false)
            }
            .font(.system(size: expanded ? 12 : 9, weight: .semibold))
            ProgressView(value: (window?.remainingPercent ?? 0) / 100)
                .progressViewStyle(LimitBar(color: meterColor, expanded: expanded))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.34), value: window?.remainingPercent)
            if expanded {
                Text(reset.map { "Сброс \($0)" } ?? (window == nil ? "Нет данных" : "Время сброса неизвестно"))
                    .foregroundStyle(.secondary).font(.system(size: 10)).lineLimit(1)
            }
        }
        .padding(.horizontal, expanded ? 10 : 6)
        .padding(.vertical, expanded ? 8 : 6)
        .frame(minWidth: expanded ? nil : 78, maxWidth: expanded ? .infinity : 78)
        .background { GlassSurface(radius: expanded ? 11 : 8, intensity: 0.12) }
        .help(reset.map { "\(title): осталось \(percent). Сброс \($0)." } ?? "\(title): \(window == nil ? "нет данных" : "осталось \(percent)")")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(window == nil ? "нет данных" : "осталось \(percent)")")
    }
}

private struct LimitBar: ProgressViewStyle {
    let color: Color
    let expanded: Bool
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(color.opacity(0.82)).frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: expanded ? 4 : 3)
    }
}

private struct PlanBadge: View {
    let plan: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(plan.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.6)
            .foregroundStyle(.secondary).padding(.horizontal, 7).padding(.vertical, 4)
            .background {
                if scheme == .dark { Capsule().strokeBorder(.white.opacity(0.17), lineWidth: 1) }
                else { Capsule().fill(.ultraThinMaterial) }
            }
    }
}

private struct Avatar: View {
    let identity: AccountIdentity?
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var tint: Color {
        if scheme == .dark { return Palette.ink }
        let colors: [Color] = [Color(red: 0.16, green: 0.64, blue: 0.74), .indigo, .teal, .purple]
        let index = Int(identity?.id.utf8.first ?? 0) % colors.count
        return colors[index]
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(colors: [scheme == .dark ? Palette.graphite : tint.opacity(0.82), tint],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let identity = identity {
                Text(identity.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
                    .font(.system(size: size * 0.31, weight: .semibold, design: .rounded))
            } else {
                Image(systemName: "person.crop.circle").font(.system(size: size * 0.44, weight: .light))
            }
        }
        .foregroundStyle(scheme == .dark ? Palette.brass : .white)
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.29)
                .strokeBorder(.white.opacity(scheme == .dark ? 0.15 : 0.47), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct ThemeTile: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: theme == .dark ? [Palette.graphite, Palette.ink]
                                         : theme == .light ? [.white, .cyan.opacity(0.23)] : [.white.opacity(0.85), Palette.graphite],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 70)
                    .overlay {
                        Image(systemName: theme.icon).font(.system(size: 24, weight: .light))
                            .foregroundStyle(theme == .dark ? Palette.brass : theme == .light ? .indigo : .white)
                    }
                HStack(spacing: 5) {
                    Text(theme.title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent(scheme))
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background { GlassSurface(radius: 16, intensity: selected ? 0.49 : 0.17) }
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.accent(scheme).opacity(0.66), lineWidth: 1) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
