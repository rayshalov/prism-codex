import Darwin
import Foundation

public struct Profile: Codable, Identifiable, Equatable, Sendable {
    public let identity: AccountIdentity
    public let savedAt: Date
    public var id: String { identity.id }
    public init(identity: AccountIdentity, savedAt: Date = .now) {
        self.identity = identity
        self.savedAt = savedAt
    }
}

public struct Snapshot: Sendable {
    public let profiles: [Profile]
    public let active: AccountIdentity?
    public let activeUnsupported: Bool
}

private final class Lease {
    let fd: Int32
    init(at path: URL) throws {
        try PrivateFile.makeDirectory(path.deletingLastPathComponent())
        fd = Darwin.open(path.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw PrismError.unsafeFile }
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1 else {
            Darwin.close(fd)
            throw PrismError.unsafeFile
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw PrismError.busy
        }
    }
    deinit { Darwin.close(fd) }
}

public actor AccountStore {
    public nonisolated let home: URL
    private let root: URL
    private let secrets: any SecretStore
    private var auth: URL { home.appendingPathComponent("auth.json") }
    private var registry: URL { root.appendingPathComponent("profiles.json") }
    private var lock: URL { root.appendingPathComponent(".lock") }

    public init(home: URL, root: URL, secrets: any SecretStore = Keychain()) {
        self.home = home
        self.root = root
        self.secrets = secrets
    }

    public func snapshot() throws -> Snapshot {
        let profiles = try readRegistry().profiles
        let bytes = try PrivateFile.read(auth)
        let active = bytes.flatMap { try? Credential($0).identity }
        return Snapshot(profiles: profiles, active: active, activeUnsupported: bytes != nil && active == nil)
    }

    public func importCurrent() throws -> Profile {
        let lease = try Lease(at: lock)
        defer { withExtendedLifetime(lease) {} }
        guard let bytes = try PrivateFile.read(auth) else { throw PrismError.noCredential }
        return try register(Credential(bytes))
    }

    public func save(_ credential: Credential) throws -> Profile {
        let lease = try Lease(at: lock)
        defer { withExtendedLifetime(lease) {} }
        return try register(credential)
    }

    public func validateTarget(_ id: String) throws {
        _ = try savedCredential(id)
    }

    public func credentialForUsage(_ id: String) throws -> Credential {
        if let bytes = try PrivateFile.read(auth), let active = try? Credential(bytes), active.identity.id == id {
            return active
        }
        return try savedCredential(id)
    }

    public func remove(_ id: String) throws {
        let lease = try Lease(at: lock)
        defer { withExtendedLifetime(lease) {} }
        let snapshot = try snapshot()
        guard snapshot.active?.id != id else { throw PrismError.busy }
        let original = try readRegistry()
        guard original.profiles.contains(where: { $0.id == id }) else { throw PrismError.profileMissing }
        let remaining = original.profiles.filter { $0.id != id }
        let updated = try saveRegistry(remaining, replacing: original.bytes)
        do { try secrets.remove(id) }
        catch {
            if let previous = original.bytes {
                try PrivateFile.write(previous, to: registry, replacing: updated)
            }
            throw error
        }
    }

    @discardableResult
    public func activate(_ id: String, verify: @Sendable (AccountIdentity) async throws -> Void) async throws -> AccountIdentity {
        let lease = try Lease(at: lock)
        defer { withExtendedLifetime(lease) {} }
        let candidate = try savedCredential(id)
        let previous = try PrivateFile.read(auth)
        if let previous = previous {
            let current = try Credential(previous)
            if current.identity.id == id { return current.identity }
            _ = try register(current)
        }

        try Task.checkCancellation()
        try PrivateFile.write(candidate.data, to: auth, replacing: previous)
        do {
            try await verify(candidate.identity)
            try Task.checkCancellation()
            guard let bytes = try PrivateFile.read(auth), try Credential(bytes).identity.id == id
            else { throw PrismError.verification }
            return candidate.identity
        } catch {
            let failure = error
            do {
                if let previous = previous {
                    try PrivateFile.write(previous, to: auth, replacing: candidate.data)
                } else {
                    try PrivateFile.remove(auth, matching: candidate.data)
                }
            } catch { throw PrismError.rollback }
            throw failure
        }
    }

    private func savedCredential(_ id: String) throws -> Credential {
        guard try readRegistry().profiles.contains(where: { $0.id == id }),
              let bytes = try secrets.load(id) else { throw PrismError.profileMissing }
        let credential = try Credential(bytes)
        guard credential.identity.id == id else { throw PrismError.verification }
        return credential
    }

    private func register(_ credential: Credential) throws -> Profile {
        let original = try readRegistry()
        let profile = Profile(identity: credential.identity)
        let existed = original.profiles.contains(where: { $0.id == profile.id })
        try secrets.save(credential.data, id: profile.id)
        do {
            let profiles = original.profiles.filter { $0.id != profile.id } + [profile]
            _ = try saveRegistry(profiles, replacing: original.bytes)
            return profile
        } catch {
            if !existed { try? secrets.remove(profile.id) }
            throw error
        }
    }

    private func readRegistry() throws -> (profiles: [Profile], bytes: Data?) {
        guard let bytes = try PrivateFile.read(registry) else { return ([], nil) }
        guard let profiles = try? JSONDecoder().decode([Profile].self, from: bytes) else { throw PrismError.fileIO }
        return (profiles.sorted { $0.savedAt > $1.savedAt }, bytes)
    }

    private func saveRegistry(_ profiles: [Profile], replacing expected: Data?) throws -> Data {
        let bytes = try JSONEncoder().encode(profiles)
        try PrivateFile.write(bytes, to: registry, replacing: expected)
        return bytes
    }
}
