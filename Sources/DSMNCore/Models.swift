import Foundation

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case claudeCode
    case codex
    case grokBuild

    public var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        case .grokBuild:
            "Grok Build"
        }
    }
}

public struct RunningProcess: Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32?
    public var executable: String
    public var command: String

    public init(pid: Int32, ppid: Int32?, executable: String, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.executable = executable
        self.command = command
    }
}

public struct AgentProcess: Codable, Equatable, Sendable {
    public var pid: Int32
    public var ppid: Int32?
    public var executable: String
    public var command: String
    public var kind: AgentKind

    public init(pid: Int32, ppid: Int32?, executable: String, command: String, kind: AgentKind) {
        self.pid = pid
        self.ppid = ppid
        self.executable = executable
        self.command = command
        self.kind = kind
    }
}

public enum PowerSource: String, Codable, Sendable {
    case ac
    case battery
    case unknown
}

public struct SystemSnapshot: Codable, Equatable, Sendable {
    public var now: Date
    public var powerSource: PowerSource
    public var batteryPercent: Int?
    public var defaultRouteAvailable: Bool?
    public var lidClosed: Bool?

    public init(
        now: Date = Date(),
        powerSource: PowerSource = .unknown,
        batteryPercent: Int? = nil,
        defaultRouteAvailable: Bool? = nil,
        lidClosed: Bool? = nil
    ) {
        self.now = now
        self.powerSource = powerSource
        self.batteryPercent = batteryPercent
        self.defaultRouteAvailable = defaultRouteAvailable
        self.lidClosed = lidClosed
    }
}

public struct SafetyPolicy: Codable, Equatable, Sendable {
    public var minimumBatteryPercent: Int
    public var maxManualDurationMinutes: Int
    public var noAgentGraceSeconds: Int
    public var lidOpenGraceSeconds: Int
    public var noRouteGraceSeconds: Int

    public init(
        minimumBatteryPercent: Int = 20,
        maxManualDurationMinutes: Int = 8 * 60,
        noAgentGraceSeconds: Int = 5 * 60,
        lidOpenGraceSeconds: Int = 5 * 60,
        noRouteGraceSeconds: Int = 15 * 60
    ) {
        self.minimumBatteryPercent = minimumBatteryPercent
        self.maxManualDurationMinutes = maxManualDurationMinutes
        self.noAgentGraceSeconds = noAgentGraceSeconds
        self.lidOpenGraceSeconds = lidOpenGraceSeconds
        self.noRouteGraceSeconds = noRouteGraceSeconds
    }
}

public struct DSMNState: Codable, Equatable, Sendable {
    public var autoEnabled: Bool
    public var manualUntil: Date?
    public var ownsSleepDisable: Bool
    public var lastActivationReason: String?
    public var lastStopReason: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        autoEnabled: Bool = false,
        manualUntil: Date? = nil,
        ownsSleepDisable: Bool = false,
        lastActivationReason: String? = nil,
        lastStopReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.autoEnabled = autoEnabled
        self.manualUntil = manualUntil
        self.ownsSleepDisable = ownsSleepDisable
        self.lastActivationReason = lastActivationReason
        self.lastStopReason = lastStopReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func manualRemainingSeconds(at date: Date) -> Int? {
        guard let manualUntil else {
            return nil
        }

        return max(0, Int(manualUntil.timeIntervalSince(date).rounded(.down)))
    }

    public func manualIsActive(at date: Date) -> Bool {
        guard let remaining = manualRemainingSeconds(at: date) else {
            return false
        }

        return remaining > 0
    }
}

public enum AutoAction: String, Sendable {
    case on
    case off
    case toggle
}

