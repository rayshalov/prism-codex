import Darwin
import Foundation

public struct CodexRuntime: Sendable {
    public let executable: URL

    public init(executable: URL) { self.executable = executable }

    public static func locate() throws -> CodexRuntime {
        let user = FileManager.default.homeDirectoryForCurrentUser
        let direct = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            user.appendingPathComponent(".local/bin/codex").path
        ]
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { String($0) + "/codex" } ?? []
        guard let executable = (direct + path).first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { throw PrismError.runtimeMissing }
        return CodexRuntime(executable: URL(fileURLWithPath: executable))
    }

    public func checkStorage(home: URL) async throws {
        try await connected(home: home) { session in try await fileStorage(session) }
    }

    public func verify(_ expected: AccountIdentity, home: URL) async throws {
        try await connected(home: home) { session in
            try await fileStorage(session)
            let result = try await session.request("account/read", ["refreshToken": false])
            guard let account = result["account"] as? [String: Any], account["type"] as? String == "chatgpt" else {
                throw PrismError.verification
            }
            let email = account["email"] as? String
            if let expectedEmail = expected.email,
               email?.caseInsensitiveCompare(expectedEmail) != .orderedSame {
                throw PrismError.verification
            }
            let workspace = account["accountId"] as? String ?? account["chatgptAccountId"] as? String
            if let workspace = workspace, workspace != expected.workspace { throw PrismError.verification }
        }
    }

    public func signIn(open: @Sendable (URL) async -> Bool) async throws -> Credential {
        let staging = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: staging) }
        return try await connected(home: staging, mode: .browser) { session in
            let result = try await session.request("account/login/start", ["type": "chatgpt"])
            guard let address = result["authUrl"] as? String,
                  let url = URL(string: address), url.scheme == "https",
                  url.user == nil, url.password == nil, url.port == nil || url.port == 443,
                  let host = url.host, ["auth.openai.com", "auth0.openai.com", "chatgpt.com"].contains(host)
            else { throw PrismError.loginFailed }
            guard await open(url) else { throw PrismError.browser }
            let completion = try await session.notification("account/login/completed", timeout: 600)
            guard completion["success"] as? Bool == true,
                  let data = try PrivateFile.read(staging.appendingPathComponent("auth.json"))
            else { throw PrismError.loginFailed }
            return try Credential(data)
        }
    }

    public func usage(for credential: Credential) async throws -> UsageLimits {
        let staging = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: staging) }
        return try await connected(home: staging, mode: .usage) { session in
            var params: [String: Any] = ["type": "chatgptAuthTokens", "accessToken": credential.accessToken,
                                         "chatgptAccountId": credential.identity.workspace]
            if let plan = credential.identity.plan { params["chatgptPlanType"] = plan }
            let login = try await session.request("account/login/start", params)
            guard login["type"] as? String == "chatgptAuthTokens" else { throw PrismError.runtimeFailed }
            return try await UsageLimits.decode(session.request("account/rateLimits/read", [:]))
        }
    }

    private func temporaryHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prism-session-\(UUID().uuidString)", isDirectory: true)
        try PrivateFile.makeDirectory(directory)
        return directory
    }

    private func connected<T>(home: URL, mode: SessionMode = .configured,
                              _ work: (Session) async throws -> T) async throws -> T {
        let session = try Session(executable: executable, home: home, mode: mode)
        do {
            try await session.initialize(experimental: mode == .usage)
            let result = try await work(session)
            await session.stop()
            return result
        } catch {
            await session.stop()
            throw error
        }
    }

    private func fileStorage(_ session: Session) async throws {
        let result = try await session.request("config/read", ["includeLayers": false])
        guard let config = result["config"] as? [String: Any],
              config["cli_auth_credentials_store"] as? String == "file" else { throw PrismError.storageMode }
    }
}

private enum SessionMode {
    case configured, browser, usage

    var arguments: [String] {
        switch self {
        case .configured: return []
        case .browser: return ["-c", "cli_auth_credentials_store=\"file\""]
        case .usage: return ["-c", "cli_auth_credentials_store=\"ephemeral\""]
        }
    }
}

private final class Session {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffered = Data()
    private var pending: [[String: Any]] = []
    private var nextID = 0

    init(executable: URL, home: URL, mode: SessionMode) throws {
        try Task.checkCancellation()
        var environment = ProcessInfo.processInfo.environment
        for key in ["OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "CODEX_AUTH_TOKEN",
                    "OPENAI_BASE_URL", "OPENAI_CHATGPT_TOKEN"] {
            environment.removeValue(forKey: key)
        }
        environment["CODEX_HOME"] = home.path
        process.executableURL = executable
        process.arguments = mode.arguments + ["app-server", "--listen", "stdio://"]
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let read = output.fileHandleForReading.fileDescriptor
        guard fcntl(read, F_SETFL, O_NONBLOCK) == 0,
              fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw PrismError.runtimeFailed
        }
        do { try process.run() }
        catch { throw PrismError.runtimeFailed }
    }

    func initialize(experimental: Bool) async throws {
        _ = try await request("initialize", [
            "clientInfo": ["name": "prism_switch", "version": "1.0.0"],
            "capabilities": ["experimentalApi": experimental]
        ])
        try send(["method": "initialized"])
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send(["id": id, "method": method, "params": params])
        let envelope = try await receive(timeout: 12) { $0["method"] == nil && ($0["id"] as? Int) == id }
        guard let result = envelope["result"] as? [String: Any] else { throw PrismError.runtimeFailed }
        return result
    }

    func notification(_ method: String, timeout: TimeInterval) async throws -> [String: Any] {
        let envelope = try await receive(timeout: timeout) { $0["method"] as? String == method }
        guard let params = envelope["params"] as? [String: Any] else { throw PrismError.runtimeFailed }
        return params
    }

    func stop() async {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        for _ in 0..<24 {
            if !process.isRunning { break }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(25)) {
                    continuation.resume()
                }
            }
        }
        try? output.fileHandleForReading.close()
    }

    private func send(_ object: [String: Any]) throws {
        try Task.checkCancellation()
        do {
            var bytes = try JSONSerialization.data(withJSONObject: object)
            bytes.append(10)
            try input.fileHandleForWriting.write(contentsOf: bytes)
        } catch { throw PrismError.runtimeFailed }
    }

    private func receive(timeout: TimeInterval,
                         matching: ([String: Any]) -> Bool) async throws -> [String: Any] {
        if let index = pending.firstIndex(where: matching) { return pending.remove(at: index) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let fd = output.fileHandleForReading.fileDescriptor
        var chunk = [UInt8](repeating: 0, count: 8192)
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            while let newline = buffered.firstIndex(of: 10) {
                let line = Data(buffered[..<newline])
                buffered.removeSubrange(...newline)
                guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
                if object["method"] as? String == "account/chatgptAuthTokens/refresh", let id = object["id"] {
                    let error: [String: Any] = ["code": -32000, "message": "Read-only session"]
                    try send(["id": id, "error": error])
                    throw PrismError.usageReauthentication
                }
                if matching(object) { return object }
                if pending.count < 64 { pending.append(object) }
            }
            let count = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                buffered.append(contentsOf: chunk.prefix(count))
                guard buffered.count < 2_000_000 else { throw PrismError.runtimeFailed }
            } else if count == 0 {
                throw PrismError.runtimeFailed
            } else if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                try await Task.sleep(nanoseconds: 35_000_000)
            } else {
                throw PrismError.runtimeFailed
            }
        }
        throw PrismError.timeout
    }
}
