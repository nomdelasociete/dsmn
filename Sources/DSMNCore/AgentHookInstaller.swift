import Foundation

public enum AgentHookTarget: String, CaseIterable, Codable, Hashable, Sendable {
    case claude
    case codex
    case grok
    case pi

    public static func parse(_ value: String) throws -> AgentHookTarget {
        guard let target = AgentHookTarget(rawValue: value) else {
            throw DSMNError.invalidCommand("install-hooks target \(value)")
        }

        return target
    }
}

public struct AgentHookInstallReport: Codable, Equatable, Sendable {
    public var target: String
    public var path: String
    public var changed: Bool
    public var message: String

    public init(target: String, path: String, changed: Bool, message: String) {
        self.target = target
        self.path = path
        self.changed = changed
        self.message = message
    }
}

public struct AgentHookInstaller: Sendable {
    private static let hookEventNames = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse"
    ]

    public var homeDirectory: URL
    public var hookScriptPath: URL
    public var dsmnctlPath: String?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        hookScriptPath: URL? = nil,
        dsmnctlPath: String? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.hookScriptPath = hookScriptPath ?? homeDirectory
            .appendingPathComponent(".dsmn", isDirectory: true)
            .appendingPathComponent("dsmn-agent-hook.sh")
        self.dsmnctlPath = dsmnctlPath
    }

    public func install(targets: [AgentHookTarget] = AgentHookTarget.allCases) throws -> [AgentHookInstallReport] {
        try installHookScript()

        return try targets.map { target in
            switch target {
            case .claude:
                return try installClaudeHook()
            case .codex:
                return try installCodexHook()
            case .grok:
                return try installGrokHook()
            case .pi:
                return try installPiHook()
            }
        }
    }

    private func installHookScript() throws {
        let directory = hookScriptPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try hookScript().write(to: hookScriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath.path)
    }

    private func installClaudeHook() throws -> AgentHookInstallReport {
        let path = homeDirectory.appendingPathComponent(".claude/settings.json")
        var root = try readJSONObject(path)
        let changed = try installHook(into: &root)
        try writeJSONObject(root, to: path)

        return AgentHookInstallReport(
            target: AgentHookTarget.claude.rawValue,
            path: path.path,
            changed: changed,
            message: changed ? "installed" : "already installed"
        )
    }

    private func installCodexHook() throws -> AgentHookInstallReport {
        let directory = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("hooks.json")
        var root = try readJSONObject(path)
        let hooksChanged = try installHook(into: &root)
        try writeJSONObject(root, to: path)
        let featureChanged = try enableTomlFeature(
            in: directory.appendingPathComponent("config.toml"),
            featureName: "hooks"
        )
        let changed = hooksChanged || featureChanged

        return AgentHookInstallReport(
            target: AgentHookTarget.codex.rawValue,
            path: path.path,
            changed: changed,
            message: changed ? "installed; Codex hooks feature enabled" : "already installed"
        )
    }

    private func installGrokHook() throws -> AgentHookInstallReport {
        let directory = homeDirectory
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("dsmn.json")
        let root: [String: Any] = ["hooks": hookEventPayload()]

        let changed = try !jsonEquals(readJSONObject(path), root)
        if changed {
            try writeJSONObject(root, to: path)
        }

        return AgentHookInstallReport(
            target: AgentHookTarget.grok.rawValue,
            path: path.path,
            changed: changed,
            message: changed ? "installed" : "already installed"
        )
    }

    private func installPiHook() throws -> AgentHookInstallReport {
        let directory = homeDirectory
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("dsmn.ts")
        let payload = piExtension()
        let current = try? String(contentsOf: path, encoding: .utf8)
        let changed = current != payload

        if changed {
            try payload.write(to: path, atomically: true, encoding: .utf8)
        }

        return AgentHookInstallReport(
            target: AgentHookTarget.pi.rawValue,
            path: path.path,
            changed: changed,
            message: changed ? "installed" : "already installed"
        )
    }

    private func installHook(into root: inout [String: Any]) throws -> Bool {
        var changed = false
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventName in Self.hookEventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            let newGroup = hookGroup()

            let originalCount = groups.count
            groups = groups.filter { group in
                jsonEquals(group, newGroup) || !containsLegacyAwakeHook(group)
            }
            if groups.count != originalCount {
                changed = true
            }

            if !groups.contains(where: { jsonEquals($0, newGroup) }) {
                groups.append(newGroup)
                changed = true
            }

            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        return changed
    }

    private func hookEventPayload() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: Self.hookEventNames.map { eventName in
            (eventName, [hookGroup()])
        })
    }

    private func hookGroup() -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": hookScriptPath.path,
                    "timeout": 5
                ]
            ]
        ]
    }

    private func piExtension() -> String {
        let hookPath = jsonStringLiteral(hookScriptPath.path)

        return """
        import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
        import { spawn } from "node:child_process";

        const hookPath = \(hookPath);

        function trigger(eventName: string) {
          try {
            const child = spawn(hookPath, [], {
              detached: true,
              stdio: "ignore",
              env: {
                ...process.env,
                DSMN_HOOK_AGENT: "pi",
                DSMN_HOOK_EVENT: eventName,
              },
            });
            child.on("error", () => {});
            child.unref();
          } catch {
            // Keep Pi fail-open if dsmn is unavailable.
          }
        }

        export default function (pi: ExtensionAPI) {
          pi.on("session_start", async () => trigger("session_start"));
          pi.on("input", async () => trigger("input"));
          pi.on("turn_start", async () => trigger("turn_start"));
          pi.on("tool_call", async () => trigger("tool_call"));
          pi.on("tool_result", async () => trigger("tool_result"));
          pi.on("turn_end", async () => trigger("turn_end"));
        }

        """
    }

    private func containsLegacyAwakeHook(_ group: [String: Any]) -> Bool {
        guard let hooks = group["hooks"] as? [[String: Any]] else {
            return false
        }

        let hasMatcher = (group["matcher"] as? String)?.isEmpty == false
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else {
                return false
            }

            return command.contains("dsmn-agent-hook.sh")
                || command.contains("claude-hook.sh")
                || (command.contains("caffeinate") && !hasMatcher && hooks.count == 1)
        }
    }

    private func readJSONObject(_ path: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return [:]
        }

        let data = try Data(contentsOf: path)
        guard !data.isEmpty else {
            return [:]
        }

        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func writeJSONObject(_ object: [String: Any], to path: URL) throws {
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        var payload = String(data: data, encoding: .utf8) ?? "{}"
        payload += "\n"
        try payload.write(to: path, atomically: true, encoding: .utf8)
    }

    private func enableTomlFeature(in path: URL, featureName: String) throws -> Bool {
        let original = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        var lines = original.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }

        guard !lines.isEmpty else {
            try "[features]\n\(featureName) = true\n".write(to: path, atomically: true, encoding: .utf8)
            return true
        }

        let featuresRange = findTomlSection(named: "features", in: lines)
        guard let featuresRange else {
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("\(featureName) = true")
            try writeTomlLines(lines, to: path)
            return true
        }

        for index in featuresRange.lowerBound..<featuresRange.upperBound {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let uncommented = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard uncommented.hasPrefix("\(featureName)") else {
                continue
            }

            let parts = uncommented.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.first == featureName else {
                continue
            }

            if parts.count == 2, parts[1] == "true" {
                return false
            }

            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            lines[index] = "\(indentation)\(featureName) = true"
            try writeTomlLines(lines, to: path)
            return true
        }

        lines.insert("\(featureName) = true", at: featuresRange.upperBound)
        try writeTomlLines(lines, to: path)
        return true
    }

    private func findTomlSection(named name: String, in lines: [String]) -> Range<Int>? {
        var sectionStart: Int?
        var sectionEnd: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
                continue
            }

            if sectionStart == nil, trimmed == "[\(name)]" {
                sectionStart = index + 1
                continue
            }

            if sectionStart != nil {
                sectionEnd = index
                break
            }
        }

        guard let sectionStart else {
            return nil
        }

        return sectionStart..<(sectionEnd ?? lines.count)
    }

    private func writeTomlLines(_ lines: [String], to path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    private func jsonEquals(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(lhs),
              JSONSerialization.isValidJSONObject(rhs),
              let lhsData = try? JSONSerialization.data(withJSONObject: lhs, options: [.sortedKeys]),
              let rhsData = try? JSONSerialization.data(withJSONObject: rhs, options: [.sortedKeys])
        else {
            return false
        }

        return lhsData == rhsData
    }

    private func hookScript() -> String {
        let currentDsmnctlPath = dsmnctlPath ?? CommandLine.arguments.first ?? ""
        let escapedDsmnctlPath = shellSingleQuoted(currentDsmnctlPath)

        return """
        #!/usr/bin/env bash
        set -u

        MODE="${DSMN_HOOK_MODE:-manual}"
        MINUTES="${DSMN_HOOK_MINUTES:-20}"
        FALLBACK_SECONDS="${DSMN_HOOK_FALLBACK_SECONDS:-600}"
        LOG_PATH="${DSMN_HOOK_LOG:-/tmp/dsmn-agent-hook.log}"

        log_event() {
          printf '%s %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_PATH" 2>/dev/null || true
        }

        resolve_dsmnctl() {
          if [[ -n "${DSMNCTL_PATH:-}" && -x "$DSMNCTL_PATH" ]]; then
            printf '%s\\n' "$DSMNCTL_PATH"
            return 0
          fi

          local candidates=(
            \(escapedDsmnctlPath)
            "/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"
            "$HOME/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"
            "$HOME/Documents/Github/NomDeLaSociete/dsmn/dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl"
            "$HOME/Documents/Github/NomDeLaSociete/dsmn/.build/debug/dsmnctl"
          )

          local candidate
          for candidate in "${candidates[@]}"; do
            if [[ -x "$candidate" ]]; then
              printf '%s\\n' "$candidate"
              return 0
            fi
          done

          return 1
        }

        fallback_caffeinate() {
          if ! command -v caffeinate >/dev/null 2>&1; then
            log_event "fallback unavailable: caffeinate not found"
            return 0
          fi

          caffeinate -is -t "$FALLBACK_SECONDS" >/dev/null 2>&1 &
          disown "$!" 2>/dev/null || true
          log_event "fallback caffeinate started seconds=$FALLBACK_SECONDS"
        }

        ctl="$(resolve_dsmnctl || true)"
        if [[ -z "$ctl" ]]; then
          log_event "dsmnctl not found"
          fallback_caffeinate
          exit 0
        fi

        case "$MODE" in
        manual)
          if ! "$ctl" manual --minutes "$MINUTES" --json >/dev/null 2>&1; then
            log_event "dsmn manual failed ctl=$ctl"
            fallback_caffeinate
            exit 0
          fi
          ;;
        auto)
          if ! "$ctl" auto on --json >/dev/null 2>&1; then
            log_event "dsmn auto failed ctl=$ctl"
            fallback_caffeinate
            exit 0
          fi
          ;;
        *)
          log_event "invalid mode=$MODE"
          fallback_caffeinate
          exit 0
          ;;
        esac

        doctor="$("$ctl" doctor 2>&1 || true)"

        if grep -q "Status source: local fallback" <<<"$doctor"; then
          log_event "helper unavailable; using fallback"
          fallback_caffeinate
          exit 0
        fi

        if grep -q "macOS SleepDisabled: on" <<<"$doctor"; then
          log_event "dsmn active mode=$MODE minutes=$MINUTES"
        else
          log_event "dsmn helper reachable but sleep lock is off"
        fi

        exit 0
        """
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let array = String(data: data, encoding: .utf8)
        else {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        return String(array.dropFirst().dropLast())
    }
}
