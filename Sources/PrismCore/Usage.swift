import CoreFoundation
import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(remainingPercent: Double, resetsAt: Date?) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct UsageLimits: Equatable, Sendable {
    public let fiveHours: UsageWindow?
    public let week: UsageWindow?

    public init(fiveHours: UsageWindow?, week: UsageWindow?) {
        self.fiveHours = fiveHours
        self.week = week
    }

    static func decode(_ result: [String: Any]) throws -> UsageLimits {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let legacy = result["rateLimits"] as? [String: Any]
        let legacyID = legacy?["limitId"] as? String
        guard let codex = buckets?["codex"] as? [String: Any]
                ?? (legacyID == nil || legacyID == "codex" ? legacy : nil) else {
            if result.keys.contains("rateLimits") || result.keys.contains("rateLimitsByLimitId") {
                return UsageLimits(fiveHours: nil, week: nil)
            }
            throw PrismError.runtimeFailed
        }

        var windows: [Int: UsageWindow] = [:]
        for name in ["primary", "secondary"] {
            guard let value = codex[name] as? [String: Any],
                  let duration = number(value["windowDurationMins"] ?? value["durationMinutes"]),
                  duration == 300 || duration == 10_080,
                  let used = number(value["usedPercent"]), used >= 0 else { continue }
            let reset = number(value["resetsAt"]).flatMap {
                $0 > 0 && $0 < 253_402_300_800 ? Date(timeIntervalSince1970: $0) : nil
            }
            let key = Int(duration)
            if windows[key] == nil {
                windows[key] = UsageWindow(remainingPercent: max(0, 100 - used), resetsAt: reset)
            }
        }
        return UsageLimits(fiveHours: windows[300], week: windows[10_080])
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
}
