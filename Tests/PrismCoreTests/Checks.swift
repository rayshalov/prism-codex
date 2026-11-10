import Darwin
import Foundation
import PrismCore

private struct CheckFailure: Error { let label: String }

private func check(_ passed: Bool, _ label: String) throws {
    if !passed { throw CheckFailure(label: label) }
}

private final class MemorySecrets: SecretStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    func load(_ id: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[id] }
    func save(_ data: Data, id: String) throws { lock.lock(); defer { lock.unlock() }; values[id] = data }
    func remove(_ id: String) throws { lock.lock(); defer { lock.unlock() }; values[id] = nil }
}

private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    var waiting: Bool { continuation != nil }
    func release() { continuation?.resume(); continuation = nil }
}

private func fixture(_ user: String, workspace: String = "test-team", revision: String = "1") throws -> Credential {
    let claims: [String: Any] = [
        "sub": user, "email": "\(user)@example.com", "name": user.capitalized,
        "https://api.openai.com/auth": ["chatgpt_user_id": user, "chatgpt_account_id": workspace, "chatgpt_plan_type": "plus"]
    ]
    let jwt = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
        .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    let value: [String: Any] = [
        "auth_mode": "chatgpt",
        "tokens": ["id_token": "test.\(jwt).test", "account_id": workspace, "access_token": "fixture-\(revision)",
                   "refresh_token": "fixture-only-\(revision)"]
    ]
    return try Credential(JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
}

private func record(_ name: String, _ body: () async throws -> Void) async throws {
    try await body()
    print("PASS \(name)")
}

@main
struct Checks {
    static func main() async {
        if CommandLine.arguments.contains("app-server") {
            do { try mockServer() }
            catch { exit(2) }
            return
        }
        do {
            try await tests()
        } catch let failure as CheckFailure {
            print("FAIL \(failure.label)")
            exit(1)
        } catch {
            print("FAIL \(String(describing: error))")
            exit(1)
        }
    }

    static func tests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prism-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("codex")
        let auth = home.appendingPathComponent("auth.json")
        let appData = root.appendingPathComponent("registry")
        let memory = MemorySecrets()
        let store = AccountStore(home: home, root: appData, secrets: memory)
        let alex = try fixture("alex"), rotatedAlex = try fixture("alex", revision: "2"), dana = try fixture("dana")
        let stage = root.appendingPathComponent("rpc")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let runtime = CodexRuntime(executable: executable)

        try await record("distinct identities sharing a workspace and stable token refresh") {
            try check(alex.identity.id != dana.identity.id, "same workspace collapsed two users")
            try check(alex.identity.id == rotatedAlex.identity.id, "refresh changed the identity")
            let otherWorkspace = try fixture("alex", workspace: "different")
            try check(alex.identity.id != otherWorkspace.identity.id, "different workspaces collapsed")
        }

        try await record("import, switch, and preserve freshly refreshed previous credentials") {
            try PrivateFile.write(alex.data, to: auth, replacing: nil)
            _ = try await store.importCurrent()
            _ = try await store.save(dana)
            try PrivateFile.write(rotatedAlex.data, to: auth, replacing: alex.data)
            let selected = try await store.activate(dana.identity.id) { expected in
                let data = try PrivateFile.read(auth)
                try check(data == dana.data && expected.id == dana.identity.id, "wrong staged credential")
            }
            let saved = try memory.load(alex.identity.id)
            let snapshot = try await store.snapshot()
            let mode = try FileManager.default.attributesOfItem(atPath: auth.path)[.posixPermissions] as? Int
            try check(selected.id == dana.identity.id && snapshot.active?.id == selected.id &&
                      snapshot.profiles.count == 2 && saved == rotatedAlex.data && mode == 0o600, "incorrect commit")
        }

        try await record("verification failure restores original bytes") {
            do {
                _ = try await store.activate(alex.identity.id) { _ in throw PrismError.verification }
                throw CheckFailure(label: "verification accepted a failure")
            } catch PrismError.verification {}
            let data = try PrivateFile.read(auth)
            try check(data == dana.data, "rollback did not restore exact bytes")
        }

        try await record("failed activation with no previous login removes staged credential") {
            let empty = root.appendingPathComponent("empty")
            let other = AccountStore(home: empty, root: root.appendingPathComponent("other"), secrets: MemorySecrets())
            _ = try await other.save(alex)
            do {
                _ = try await other.activate(alex.identity.id) { _ in throw PrismError.verification }
                throw CheckFailure(label: "failed initial activation appeared successful")
            } catch PrismError.verification {}
            let data = try PrivateFile.read(empty.appendingPathComponent("auth.json"))
            try check(data == nil, "failed first activation left an active credential")
        }

        try await record("corrupt or mismatched saved credential cannot overwrite active account") {
            try memory.save(dana.data, id: alex.identity.id)
            do {
                _ = try await store.activate(alex.identity.id) { _ in throw CheckFailure(label: "verifier called on wrong identity") }
                throw CheckFailure(label: "mismatch accepted")
            } catch PrismError.verification {}
            try memory.save(rotatedAlex.data, id: alex.identity.id)
            let data = try PrivateFile.read(auth)
            try check(data == dana.data, "mismatch altered auth.json")
        }

        try await record("concurrent operations are excluded while verification is pending") {
            let gate = Gate()
            let task = Task { try await store.activate(alex.identity.id) { _ in await gate.wait() } }
            for _ in 0..<100 {
                if await gate.waiting { break }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            let waiting = await gate.waiting
            try check(waiting, "verification did not start")
            let second = AccountStore(home: home, root: appData, secrets: memory)
            do {
                _ = try await second.importCurrent()
                await gate.release()
                _ = try await task.value
                throw CheckFailure(label: "second instance bypassed lease")
            } catch PrismError.busy {}
            task.cancel()
            await gate.release()
            do {
                _ = try await task.value
                throw CheckFailure(label: "cancelled verification committed")
            } catch is CancellationError {}
            let data = try PrivateFile.read(auth)
            try check(data == dana.data, "cancelled transaction failed to roll back")
        }

        try await record("external replacement is preserved if rollback would overwrite it") {
            let third = try fixture("third")
            do {
                _ = try await store.activate(alex.identity.id) { _ in
                    try PrivateFile.write(third.data, to: auth, replacing: rotatedAlex.data)
                    throw PrismError.verification
                }
                throw CheckFailure(label: "concurrent change accepted")
            } catch PrismError.rollback {}
            let data = try PrivateFile.read(auth)
            try check(data == third.data, "rolled back over newer external credential")
        }

        try await record("symlink and stale replacement are refused") {
            let marker = root.appendingPathComponent("outside")
            let link = root.appendingPathComponent("link")
            try PrivateFile.write(Data([1]), to: marker, replacing: nil)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: marker)
            do {
                try PrivateFile.write(Data([2]), to: link, replacing: nil)
                throw CheckFailure(label: "symlink accepted")
            } catch PrismError.unsafeFile {}
            do {
                try PrivateFile.write(Data([2]), to: marker, replacing: nil)
                throw CheckFailure(label: "stale replace succeeded")
            } catch PrismError.changed {}
            let data = try PrivateFile.read(marker)
            try check(data == Data([1]), "unsafe write modified the target")
        }

        try await record("browser login uses a temporary CODEX_HOME and leaves active auth unchanged") {
            let before = try PrivateFile.read(auth)
            let credential = try await runtime.signIn { url in url.host == "auth.openai.com" }
            let after = try PrivateFile.read(auth)
            try check(credential.identity.id == dana.identity.id && before == after, "sign-in touched active auth")
        }

        try await record("RPC checks effective file mode and verifies the selected identity") {
            try await runtime.checkStorage(home: stage)
            try await runtime.verify(dana.identity, home: stage)
            do {
                try await runtime.verify(alex.identity, home: stage)
                throw CheckFailure(label: "RPC accepted wrong email")
            } catch PrismError.verification {}
            try Data().write(to: stage.appendingPathComponent("use-keyring"))
            do {
                try await runtime.checkStorage(home: stage)
                throw CheckFailure(label: "keyring configuration accepted")
            } catch PrismError.storageMode {}
        }

        try await record("usage picks the current credential or the matching saved credential") {
            let active = try fixture("third")
            let fresh = try fixture("third", revision: "3")
            _ = try await store.save(active)
            let before = try PrivateFile.read(auth)
            try PrivateFile.write(fresh.data, to: auth, replacing: before)
            let current = try await store.credentialForUsage(active.identity.id)
            let inactive = try await store.credentialForUsage(dana.identity.id)
            let unchanged = try PrivateFile.read(auth)
            try check(current.data == fresh.data && inactive.data == dana.data && unchanged == fresh.data,
                      "quota read picked stale or wrong credentials")
        }

        try await record("usage selects the Codex bucket and identifies both durations regardless of order") {
            let before = try PrivateFile.read(auth)
            let usage = try await runtime.usage(for: dana)
            let after = try PrivateFile.read(auth)
            try check(usage.fiveHours?.remainingPercent == 67.5 && usage.week?.remainingPercent == 0 &&
                      usage.week?.resetsAt == Date(timeIntervalSince1970: 1_794_000_000) && before == after,
                      "incorrect windows or live auth changed")
        }

        try await record("missing windows and reset timestamps remain unknown") {
            let partial = try await runtime.usage(for: fixture("dana", revision: "partial"))
            try check(partial.fiveHours?.remainingPercent == 44 && partial.fiveHours?.resetsAt == nil &&
                      partial.week == nil, "unknown window displayed as an allowance")
        }

        try await record("expired quota token refuses a refresh instead of touching saved sessions") {
            let expired = try fixture("dana", revision: "expired")
            let before = try PrivateFile.read(auth)
            do {
                _ = try await runtime.usage(for: expired)
                throw CheckFailure(label: "expired quota token was renewed")
            } catch PrismError.usageReauthentication {}
            let after = try PrivateFile.read(auth)
            try check(before == after, "expired quota attempt changed auth.json")
        }

        if CommandLine.arguments.contains("--live-runtime") {
            try await record("installed Codex responds over stdio in a new isolated home") {
                let isolated = root.appendingPathComponent("live-runtime")
                try FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                try await CodexRuntime.locate().checkStorage(home: isolated)
            }
        }
        if CommandLine.arguments.contains("--keychain") {
            try await record("Keychain save, update and deletion of a synthetic test item") {
                let keychain = Keychain(service: "local.prism.tests.\(UUID().uuidString)")
                let key = "fixture"
                defer { try? keychain.remove(key) }
                try keychain.save(Data([1, 2]), id: key)
                let first = try keychain.load(key)
                try keychain.save(Data([3]), id: key)
                let second = try keychain.load(key)
                try keychain.remove(key)
                let removed = try keychain.load(key)
                try check(first == Data([1, 2]) && second == Data([3]) && removed == nil, "Keychain round trip")
            }
        }
    }

    static func mockServer() throws {
        let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CODEX_HOME"]!)
        var experimental = false, accessToken: String?
        func send(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            FileHandle.standardOutput.write(data + Data([10]))
        }
        while let line = readLine() {
            guard let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = request["id"] as? Int, let method = request["method"] as? String else { continue }
            switch method {
            case "initialize":
                let params = request["params"] as? [String: Any]
                let capabilities = params?["capabilities"] as? [String: Any]
                experimental = capabilities?["experimentalApi"] as? Bool == true
                try send(["id": id, "result": ["userAgent": "fixture"]])
            case "config/read":
                let mode = FileManager.default.fileExists(atPath: home.appendingPathComponent("use-keyring").path) ? "keyring" : "file"
                try send(["id": id, "result": ["config": ["cli_auth_credentials_store": mode]]])
            case "account/read":
                try send(["id": id, "result": ["account": ["type": "chatgpt", "email": "DANA@example.com"]]])
            case "account/login/start":
                let params = request["params"] as? [String: Any]
                let auth = home.appendingPathComponent("auth.json")
                if params?["type"] as? String == "chatgptAuthTokens" {
                    let exists = try PrivateFile.read(auth) != nil
                    guard experimental, !exists, params?["refreshToken"] == nil, params?["chatgptAccountId"] as? String == "test-team",
                          CommandLine.arguments.contains("cli_auth_credentials_store=\"ephemeral\""),
                          let token = params?["accessToken"] as? String else { throw CheckFailure(label: "unsafe quota request") }
                    accessToken = token
                    try send(["id": id, "result": ["type": "chatgptAuthTokens"]])
                } else {
                    try send(["id": id, "result": ["type": "chatgpt", "authUrl": "https://auth.openai.com/fixture"]])
                    try PrivateFile.write(fixture("dana").data, to: auth, replacing: nil)
                    try send(["method": "account/login/completed", "params": ["success": true]])
                }
            case "account/rateLimits/read":
                guard let token = accessToken else { throw CheckFailure(label: "missing access token") }
                if token == "fixture-expired" {
                    try send(["id": id, "method": "account/chatgptAuthTokens/refresh", "params": ["reason": "unauthorized"]])
                } else if token == "fixture-partial" {
                    let limits: [String: Any] = ["primary": ["windowDurationMins": 300, "usedPercent": 56],
                                                  "secondary": ["windowDurationMins": 15, "usedPercent": 0]]
                    try send(["id": id, "result": ["rateLimits": limits]])
                } else {
                    let limits: [String: Any] = ["primary": ["windowDurationMins": 10_080, "usedPercent": 100, "resetsAt": 1_794_000_000],
                                                  "secondary": ["windowDurationMins": 300, "usedPercent": 32.5]]
                    let result: [String: Any] = ["rateLimits": ["limitId": "codex_other"], "rateLimitsByLimitId": ["codex": limits]]
                    try send(["id": id, "result": result])
                }
            default:
                try send(["id": id, "error": ["code": -32601]])
            }
        }
    }
}
