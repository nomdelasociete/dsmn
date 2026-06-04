import Foundation

public enum AgentHookTarget: String, CaseIterable, Codable, Hashable, Sendable {
    case claude
    case codex
    case grok
    case pi

    public static func parse(_ value: String) throws -> AgentHookTarget {
        guard let target = AgentHookTarget(rawValue: value) else {
            throw DSMNError.invalidCommand("hook target \(value)")
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

    public func uninstall(targets: [AgentHookTarget] = AgentHookTarget.allCases) throws -> [AgentHookInstallReport] {
        var reports = try targets.map { target in
            switch target {
            case .claude:
                return try uninstallClaudeHook()
            case .codex:
                return try uninstallCodexHook()
            case .grok:
                return try uninstallGrokHook()
            case .pi:
                return try uninstallPiHook()
            }
        }

        if Set(targets) == Set(AgentHookTarget.allCases) {
            reports.append(try uninstallHookScript())
        }

        return reports
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
        let changed = try installHook(into: &root, target: .claude)
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
        let hooksChanged = try installHook(into: &root, target: .codex)
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
        let root: [String: Any] = ["hooks": hookEventPayload(target: .grok)]

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

    private func uninstallClaudeHook() throws -> AgentHookInstallReport {
        let path = homeDirectory.appendingPathComponent(".claude/settings.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            return AgentHookInstallReport(
                target: AgentHookTarget.claude.rawValue,
                path: path.path,
                changed: false,
                message: "not installed"
            )
        }

        var root = try readJSONObject(path)
        let changed = try uninstallHook(from: &root, target: .claude)
        if changed {
            try writeJSONObject(root, to: path)
        }

        return AgentHookInstallReport(
            target: AgentHookTarget.claude.rawValue,
            path: path.path,
            changed: changed,
            message: changed ? "removed" : "not installed"
        )
    }

    private func uninstallCodexHook() throws -> AgentHookInstallReport {
        let path = homeDirectory.appendingPathComponent(".codex/hooks.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            return AgentHookInstallReport(
                target: AgentHookTarget.codex.rawValue,
                path: path.path,
                changed: false,
                message: "not installed"
            )
        }

        var root = try readJSONObject(path)
        let changed = try uninstallHook(from: &root, target: .codex)
        if changed {
            try writeJSONObject(root, to: path)
        }

        return AgentHookInstallReport(
            target: AgentHookTarget.codex.rawValue,
            path: path.path,
            changed: changed,
            message: changed ? "removed" : "not installed"
        )
    }

    private func uninstallGrokHook() throws -> AgentHookInstallReport {
        let path = homeDirectory
            .appendingPathComponent(".grok", isDirectory: true)
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent("dsmn.json")

        guard FileManager.default.fileExists(atPath: path.path) else {
            return AgentHookInstallReport(
                target: AgentHookTarget.grok.rawValue,
                path: path.path,
                changed: false,
                message: "not installed"
            )
        }

        let root = try readJSONObject(path)
        let hadDsmnHooks = hookCommands(in: root).contains { $0.contains("dsmn-agent-hook.sh") }
        if hadDsmnHooks {
            try FileManager.default.removeItem(at: path)
        }

        return AgentHookInstallReport(
            target: AgentHookTarget.grok.rawValue,
            path: path.path,
            changed: hadDsmnHooks,
            message: hadDsmnHooks ? "removed" : "not installed"
        )
    }

    private func uninstallPiHook() throws -> AgentHookInstallReport {
        let path = homeDirectory
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("extensions", isDirectory: true)
            .appendingPathComponent("dsmn.ts")

        guard FileManager.default.fileExists(atPath: path.path) else {
            return AgentHookInstallReport(
                target: AgentHookTarget.pi.rawValue,
                path: path.path,
                changed: false,
                message: "not installed"
            )
        }

        let current = try String(contentsOf: path, encoding: .utf8)
        let isDsmnExtension = current.contains("dsmn-agent-hook.sh")
            && current.contains("DSMN_HOOK_AGENT: \"pi\"")
        if isDsmnExtension {
            try FileManager.default.removeItem(at: path)
        }

        return AgentHookInstallReport(
            target: AgentHookTarget.pi.rawValue,
            path: path.path,
            changed: isDsmnExtension,
            message: isDsmnExtension ? "removed" : "not installed"
        )
    }

    private func uninstallHookScript() throws -> AgentHookInstallReport {
        guard FileManager.default.fileExists(atPath: hookScriptPath.path) else {
            return AgentHookInstallReport(
                target: "hook-script",
                path: hookScriptPath.path,
                changed: false,
                message: "not present"
            )
        }

        try FileManager.default.removeItem(at: hookScriptPath)
        return AgentHookInstallReport(
            target: "hook-script",
            path: hookScriptPath.path,
            changed: true,
            message: "removed"
        )
    }

    private func installHook(into root: inout [String: Any], target: AgentHookTarget) throws -> Bool {
        var changed = false
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventName in Self.hookEventNames {
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            let newGroup = hookGroup(target: target, eventName: eventName)

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

    private func uninstallHook(from root: inout [String: Any], target: AgentHookTarget) throws -> Bool {
        guard var hooks = root["hooks"] as? [String: Any] else {
            return false
        }

        var changed = false

        for eventName in Self.hookEventNames {
            guard var groups = hooks[eventName] as? [[String: Any]] else {
                continue
            }

            groups = groups.compactMap { group in
                var updatedGroup = group
                guard let groupHooks = updatedGroup["hooks"] as? [[String: Any]] else {
                    return group
                }

                let filteredHooks = groupHooks.filter { hook in
                    !isDsmnHook(hook, target: target)
                }

                if filteredHooks.count != groupHooks.count {
                    changed = true
                }

                guard !filteredHooks.isEmpty else {
                    return nil
                }

                updatedGroup["hooks"] = filteredHooks
                return updatedGroup
            }

            if groups.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = groups
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }

        return changed
    }

    private func isDsmnHook(_ hook: [String: Any], target: AgentHookTarget) -> Bool {
        guard let command = hook["command"] as? String else {
            return false
        }

        if command.contains("claude-hook.sh") {
            return true
        }

        guard command.contains("dsmn-agent-hook.sh") else {
            return false
        }

        let agentMarker = "DSMN_HOOK_AGENT=\(shellSingleQuoted(target.rawValue))"
        let agentMarkerSingleQuoted = "DSMN_HOOK_AGENT='\(target.rawValue)'"
        return command.contains(agentMarker)
            || command.contains(agentMarkerSingleQuoted)
            || command.contains("DSMN_HOOK_AGENT=\(target.rawValue)")
    }

    private func hookCommands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else {
            return []
        }

        return hooks.values.flatMap { eventValue in
            (eventValue as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                    hook["command"] as? String
                }
            }
        }
    }

    private func hookEventPayload() -> [String: Any] {
        hookEventPayload(target: .grok)
    }

    private func hookEventPayload(target: AgentHookTarget) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: Self.hookEventNames.map { eventName in
            (eventName, [hookGroup(target: target, eventName: eventName)])
        })
    }

    private func hookGroup(target: AgentHookTarget, eventName: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": hookCommand(target: target, eventName: eventName),
                    "timeout": 5
                ]
            ]
        ]
    }

    private func hookCommand(target: AgentHookTarget, eventName: String) -> String {
        let agent = target.rawValue
        return "DSMN_HOOK_AGENT=\(shellSingleQuoted(agent)) DSMN_HOOK_EVENT=\(shellSingleQuoted(eventName)) \(shellSingleQuoted(hookScriptPath.path))"
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
        let installerDsmnctlPath = (dsmnctlPath ?? CommandLine.arguments.first ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var candidateLines = [
            "\"/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl\"",
            "\"$HOME/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl\""
        ]
        if !installerDsmnctlPath.isEmpty {
            candidateLines.append(shellSingleQuoted(installerDsmnctlPath))
        }
        let candidatesBlock = candidateLines.map { "    \($0)" }.joined(separator: "\n")

        return """
        #!/usr/bin/env bash
        set -u

        MINUTES="${DSMN_HOOK_MINUTES:-20}"
        MIN_INTERVAL_SECONDS="${DSMN_HOOK_MIN_INTERVAL_SECONDS:-120}"
        STAMP_PATH="${DSMN_HOOK_STAMP:-$HOME/.dsmn/last-extend.stamp}"
        FALLBACK_SECONDS="${DSMN_HOOK_FALLBACK_SECONDS:-600}"
        LOG_PATH="${DSMN_HOOK_LOG:-/tmp/dsmn-agent-hook.log}"
        HOOK_AGENT="${DSMN_HOOK_AGENT:-agent}"
        HOOK_EVENT="${DSMN_HOOK_EVENT:-}"
        HOOK_PAYLOAD=""
        if [[ ! -t 0 ]]; then
          HOOK_PAYLOAD="$(head -c 65536 2>/dev/null || true)"
        fi

        log_event() {
          printf '%s %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_PATH" 2>/dev/null || true
        }

        dsmnctl_bundle_version() {
          local ctl="$1"
          local app_path info_path version
          app_path="$(cd "$(dirname "$ctl")/../../.." >/dev/null 2>&1 && pwd -P || true)"
          info_path="$app_path/Contents/Info.plist"

          if [[ ! -f "$info_path" ]]; then
            printf '0\\n'
            return 0
          fi

          version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_path" 2>/dev/null || true)"
          if [[ "$version" =~ ^[0-9]+$ ]]; then
            printf '%s\\n' "$version"
          else
            printf '0\\n'
          fi
        }

        resolve_dsmnctl() {
          if [[ -n "${DSMNCTL_PATH:-}" && -x "$DSMNCTL_PATH" ]]; then
            printf '%s\\n' "$DSMNCTL_PATH"
            return 0
          fi

          local candidates=(
        \(candidatesBlock)
          )

          local candidate version best best_version
          best=""
          best_version="-1"
          for candidate in "${candidates[@]}"; do
            if [[ -x "$candidate" ]]; then
              version="$(dsmnctl_bundle_version "$candidate")"
              if (( version > best_version )); then
                best="$candidate"
                best_version="$version"
              fi
            fi
          done

          if [[ -n "$best" ]]; then
            printf '%s\\n' "$best"
            return 0
          fi

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

        requester_name() {
          case "$HOOK_AGENT" in
          claude)
            printf '%s\\n' "Claude Code"
            ;;
          codex)
            printf '%s\\n' "Codex"
            ;;
          grok)
            printf '%s\\n' "Grok Build"
            ;;
          pi)
            printf '%s\\n' "Pi"
            ;;
          *)
            printf '%s\\n' "Agent"
            ;;
          esac
        }

        json_value() {
          local key="$1"
          command -v python3 >/dev/null 2>&1 || return 0

          JSON_KEY="$key" python3 -c 'import json, os, sys; key = os.environ.get("JSON_KEY"); root = json.loads(sys.stdin.read() or "{}"); walk = lambda value: [value] + sum((walk(child) for child in (value.values() if isinstance(value, dict) else value)), []) if isinstance(value, (dict, list)) else [value]; values = [item.get(key) for item in walk(root) if isinstance(item, dict) and item.get(key) not in (None, "")]; print(str(values[0]).replace("\\n", " ").replace("\\r", " ").strip()[:200]) if values else None' <<<"$HOOK_PAYLOAD" 2>/dev/null || true
        }

        short_session() {
          local value="$1"
          value="${value##*/}"
          value="${value%.jsonl}"
          value="${value%.json}"
          printf '%.8s\\n' "$value"
        }

        hook_context() {
          local session_id cwd project session_short
          session_id="$(json_value "session_id")"
          [[ -z "$session_id" ]] && session_id="$(json_value "sessionId")"
          [[ -z "$session_id" ]] && session_id="$(json_value "conversation_id")"
          [[ -z "$session_id" ]] && session_id="$(json_value "conversationId")"
          [[ -z "$session_id" ]] && session_id="$(json_value "transcript_path")"

          cwd="$(json_value "cwd")"
          [[ -z "$cwd" ]] && cwd="$(json_value "project_dir")"
          [[ -z "$cwd" ]] && cwd="$(json_value "project")"
          [[ -z "$cwd" && -n "${PWD:-}" ]] && cwd="$PWD"

          project="${cwd##*/}"
          session_short=""
          if [[ -n "$session_id" ]]; then
            session_short="$(short_session "$session_id")"
          fi

          if [[ -n "$project" && -n "$session_short" ]]; then
            printf '%s\\n' "$project - session $session_short"
          elif [[ -n "$session_short" ]]; then
            printf '%s\\n' "session $session_short"
          elif [[ -n "$project" && "$project" != "." ]]; then
            printf '%s\\n' "$project"
          fi
        }

        hook_event() {
          if [[ -n "$HOOK_EVENT" ]]; then
            printf '%s\\n' "$HOOK_EVENT"
            return 0
          fi

          local event
          event="$(json_value "hook_event_name")"
          [[ -z "$event" ]] && event="$(json_value "hookEventName")"
          [[ -z "$event" ]] && event="$(json_value "eventName")"
          [[ -z "$event" ]] && event="$(json_value "event")"
          printf '%s\\n' "$event"
        }

        should_skip_extend() {
          local last now
          [[ -f "$STAMP_PATH" ]] || return 1

          last="$(tr -dc '0-9' <"$STAMP_PATH" 2>/dev/null || true)"
          [[ -n "$last" ]] || return 1

          now="$(date +%s)"
          if (( now - last < MIN_INTERVAL_SECONDS )); then
            return 0
          fi

          return 1
        }

        record_extend_stamp() {
          mkdir -p "$(dirname "$STAMP_PATH")" 2>/dev/null || true
          date +%s >"$STAMP_PATH" 2>/dev/null || true
        }

        ctl="$(resolve_dsmnctl || true)"
        if [[ -z "$ctl" ]]; then
          log_event "dsmnctl not found"
          fallback_caffeinate
          exit 0
        fi

        REQUESTER_NAME="$(requester_name)"
        REQUESTER_CONTEXT="$(hook_context)"
        REQUESTER_EVENT="$(hook_event)"

        if should_skip_extend; then
          log_event "dsmn extend throttled seconds=$MIN_INTERVAL_SECONDS requester=$REQUESTER_NAME event=$REQUESTER_EVENT"
          exit 0
        fi

        manual_args=(manual --minutes "$MINUTES" --extend-only --requester "$REQUESTER_NAME" --json)
        [[ -n "$REQUESTER_CONTEXT" ]] && manual_args+=(--context "$REQUESTER_CONTEXT")
        [[ -n "$REQUESTER_EVENT" ]] && manual_args+=(--event "$REQUESTER_EVENT")

        if ! "$ctl" "${manual_args[@]}" >/dev/null 2>&1; then
          log_event "dsmn manual failed ctl=$ctl requester=$REQUESTER_NAME"
          fallback_caffeinate
          exit 0
        fi

        record_extend_stamp

        doctor="$("$ctl" doctor 2>&1 || true)"

        if grep -q "Status source: local fallback" <<<"$doctor"; then
          log_event "helper unavailable; using fallback"
          fallback_caffeinate
          exit 0
        fi

        if grep -q "^Status: active" <<<"$doctor"; then
          log_event "dsmn active minutes=$MINUTES requester=$REQUESTER_NAME context=$REQUESTER_CONTEXT event=$REQUESTER_EVENT"
        elif grep -q "macOS SleepDisabled: on" <<<"$doctor"; then
          log_event "dsmn active minutes=$MINUTES requester=$REQUESTER_NAME context=$REQUESTER_CONTEXT event=$REQUESTER_EVENT"
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
