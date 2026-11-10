import CryptoKit
import Darwin
import Foundation
import Security

public enum PrismError: LocalizedError, Equatable {
    case unsupportedCredential, noCredential, unsafeFile, fileIO, busy, changed
    case keychain(Int32), profileMissing, verification, rollback, storageMode
    case runtimeMissing, runtimeFailed, timeout, browser, loginFailed, desktopBusy, desktopMissing
    case usageReauthentication

    public var errorDescription: String? {
        switch self {
        case .unsupportedCredential: return "Поддерживаются сохранённые входы в ChatGPT через Codex."
        case .noCredential: return "В выбранной папке Codex нет сохранённого входа."
        case .unsafeFile: return "Файл входа или папка недоступны для безопасной записи."
        case .fileIO: return "Не удалось прочитать или сохранить локальные данные."
        case .busy: return "Другая операция Prism уже использует хранилище."
        case .changed: return "Вход в Codex изменился во время операции. Обнови список и повтори."
        case .keychain(let code): return "Связка ключей недоступна (код \(code))."
        case .profileMissing: return "Сохранённая сессия не найдена. Добавь этот аккаунт заново."
        case .verification: return "Codex не подтвердил выбранный аккаунт."
        case .rollback: return "Не удалось восстановить предыдущий вход. Сохранённые сессии доступны в Prism."
        case .storageMode: return "Для переключения нужен файловый режим хранения входа Codex (file)."
        case .runtimeMissing: return "Исполняемый файл Codex не найден. Установи приложение или CLI Codex."
        case .runtimeFailed: return "Codex не ответил на локальный запрос."
        case .timeout: return "Время ожидания Codex истекло."
        case .browser: return "Не удалось открыть страницу входа Codex в браузере."
        case .loginFailed: return "Вход не завершился. Попробуй добавить аккаунт ещё раз."
        case .desktopBusy: return "Codex или его CLI ещё работает. Заверши активные задачи и закрой его перед сменой."
        case .desktopMissing: return "Приложение Codex не найдено. Можно открыть его вручную после установки."
        case .usageReauthentication: return "Для обновления лимитов нужен свежий вход в этот аккаунт."
        }
    }
}

public struct AccountIdentity: Codable, Equatable, Sendable {
    public let id: String
    public let workspace: String
    public let email: String?
    public let name: String?
    public let plan: String?

    public init(workspace: String, principal: String, email: String?, name: String? = nil, plan: String? = nil) {
        let digest = SHA256.hash(data: Data((workspace + "\u{0}" + principal).utf8))
        self.id = digest.map { String(format: "%02x", $0) }.joined()
        self.workspace = workspace
        self.email = email
        self.name = name
        self.plan = plan
    }

    public var displayName: String { name ?? email?.split(separator: "@").first.map(String.init) ?? "Аккаунт Codex" }
}

public struct Credential: Sendable {
    public let data: Data
    public let identity: AccountIdentity
    let accessToken: String

    public init(_ data: Data) throws {
        guard data.count <= PrivateFile.maximumBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["auth_mode"] == nil || json["auth_mode"] as? String == "chatgpt"),
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = Self.text(tokens["access_token"]),
              Self.text(tokens["refresh_token"]) != nil,
              let token = Self.text(tokens["id_token"]),
              let claims = Self.claims(token) else { throw PrismError.unsupportedCredential }

        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        let fileWorkspace = Self.text(tokens["account_id"])
        let claimWorkspace = Self.text(auth?["chatgpt_account_id"])
        guard fileWorkspace == nil || claimWorkspace == nil || fileWorkspace == claimWorkspace,
              let workspace = fileWorkspace ?? claimWorkspace else { throw PrismError.unsupportedCredential }
        let email = Self.text(claims["email"])
        guard let principal = Self.text(auth?["chatgpt_user_id"]) ?? Self.text(claims["sub"]) ?? email?.lowercased()
        else { throw PrismError.unsupportedCredential }

        self.data = data
        self.accessToken = accessToken
        identity = AccountIdentity(workspace: workspace, principal: principal, email: email,
                                   name: Self.text(claims["name"]), plan: Self.text(auth?["chatgpt_plan_type"]))
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func claims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty else { return nil }
        var body = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard let decoded = Data(base64Encoded: body) else { return nil }
        return (try? JSONSerialization.jsonObject(with: decoded)) as? [String: Any]
    }
}

public enum PrivateFile {
    public static let maximumBytes = 262_144

    static func makeDirectory(_ directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw PrismError.fileIO }
        var info = stat()
        guard Darwin.lstat(directory.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid()
        else { throw PrismError.unsafeFile }
    }

    public static func read(_ url: URL) throws -> Data? {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 {
            if errno == ENOENT { return nil }
            throw errno == ELOOP ? PrismError.unsafeFile : PrismError.fileIO
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1,
              (0...Int64(maximumBytes)).contains(info.st_size)
        else { throw PrismError.unsafeFile }
        do {
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard data.count <= maximumBytes else { throw PrismError.unsafeFile }
            return data
        } catch let error as PrismError { throw error }
        catch { throw PrismError.fileIO }
    }

    public static func write(_ data: Data, to url: URL, replacing expected: Data?) throws {
        let parent = url.deletingLastPathComponent()
        try makeDirectory(parent)
        guard data.count <= maximumBytes else { throw PrismError.fileIO }
        let temp = parent.appendingPathComponent(".prism-\(UUID().uuidString)")
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw PrismError.fileIO }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); _ = Darwin.unlink(temp.path) }
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            guard try read(url) == expected else { throw PrismError.changed }
            guard Darwin.rename(temp.path, url.path) == 0 else { throw PrismError.fileIO }
        } catch let error as PrismError { throw error }
        catch { throw PrismError.fileIO }
    }

    static func remove(_ url: URL, matching expected: Data) throws {
        guard try read(url) == expected else { throw PrismError.changed }
        guard Darwin.unlink(url.path) == 0 else { throw PrismError.fileIO }
    }
}

public protocol SecretStore: Sendable {
    func load(_ id: String) throws -> Data?
    func save(_ data: Data, id: String) throws
    func remove(_ id: String) throws
}

public struct Keychain: SecretStore {
    private let service: String
    public init(service: String = "local.prism.codex.sessions") { self.service = service }

    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: id,
         kSecAttrSynchronizable as String: false]
    }

    public func load(_ id: String) throws -> Data? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &value)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = value as? Data else { throw PrismError.keychain(code) }
        return data
    }

    public func save(_ data: Data, id: String) throws {
        let query = query(id)
        let changes = [kSecValueData as String: data]
        var code = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if code == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = "Prism · сессия Codex"
            code = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard code == errSecSuccess else { throw PrismError.keychain(code) }
    }

    public func remove(_ id: String) throws {
        let code = SecItemDelete(query(id) as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else { throw PrismError.keychain(code) }
    }
}
