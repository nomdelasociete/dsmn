import XCTest
@testable import DSMNCore

final class AgentHookInstallerTests: XCTestCase {
    func testInstallsSharedHookForClaudeCodexGrokAndPi() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )

        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "/Users/jb/.claude/hooks/safety.sh" }
                ]
              },
              {
                "hooks": [
                  { "type": "command", "command": "/usr/bin/caffeinate -is -t 600" }
                ]
              }
            ]
          }
        }
        """.write(
            to: home.appendingPathComponent(".claude/settings.json"),
            atomically: true,
            encoding: .utf8
        )
        try """
        [desktop]
        preventSleepWhileRunning = true
        """.write(
            to: home.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl")
        let reports = try installer.install()

        XCTAssertEqual(Set(reports.map(\.target)), Set(["claude", "codex", "grok", "pi"]))
        let hookScriptURL = home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hookScriptURL.path))
        let hookScript = try String(contentsOf: hookScriptURL, encoding: .utf8)
        XCTAssertTrue(hookScript.contains(#"manual_args=(manual --minutes "$MINUTES" --extend-only --requester "$REQUESTER_NAME" --json)"#))
        XCTAssertTrue(hookScript.contains("MIN_INTERVAL_SECONDS=\"${DSMN_HOOK_MIN_INTERVAL_SECONDS:-120}\""))
        XCTAssertTrue(hookScript.contains("should_skip_extend"))
        XCTAssertTrue(hookScript.contains("record_extend_stamp"))

        let claude = try readJSON(home.appendingPathComponent(".claude/settings.json"))
        let claudeCommands = hookCommands(in: claude)
        XCTAssertTrue(claudeCommands.contains("/Users/jb/.claude/hooks/safety.sh"))
        XCTAssertFalse(claudeCommands.contains { $0.contains("caffeinate") })
        let dsmnClaudeHooks = hookCommands(
            in: claude,
            events: ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse"]
        ).filter { $0.contains("dsmn-agent-hook.sh") }
        XCTAssertEqual(dsmnClaudeHooks.count, 4)
        XCTAssertFalse(dsmnClaudeHooks.contains { $0.contains("caffeinate") })
        let claudeSessionHooks = hookCommands(
            in: claude,
            events: ["SessionStart", "UserPromptSubmit"]
        )
        XCTAssertFalse(claudeSessionHooks.contains { $0.contains("caffeinate") })
        XCTAssertEqual(
            claudeCommands.filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            4
        )
        XCTAssertTrue(claudeCommands.allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='claude'") })

        let codex = try readJSON(home.appendingPathComponent(".codex/hooks.json"))
        XCTAssertEqual(
            hookCommands(in: codex).filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            4
        )
        XCTAssertTrue(hookCommands(in: codex).allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='codex'") })
        let codexConfig = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        XCTAssertTrue(codexConfig.contains("[features]\nhooks = true"))
        XCTAssertTrue(codexConfig.contains("[desktop]\npreventSleepWhileRunning = true"))

        let grok = try readJSON(home.appendingPathComponent(".grok/hooks/dsmn.json"))
        XCTAssertEqual(
            hookCommands(in: grok).filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            4
        )
        XCTAssertTrue(hookCommands(in: grok).allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='grok'") })

        let pi = try String(contentsOf: home.appendingPathComponent(".pi/agent/extensions/dsmn.ts"), encoding: .utf8)
        XCTAssertTrue(pi.contains("from \"@earendil-works/pi-coding-agent\""))
        XCTAssertTrue(pi.contains("pi.on(\"tool_call\""))
        XCTAssertTrue(pi.contains("pi.on(\"turn_start\""))
        XCTAssertTrue(pi.contains("pi.on(\"tool_result\""))
        XCTAssertTrue(pi.contains("pi.on(\"turn_end\""))
        XCTAssertTrue(pi.contains("child.on(\"error\""))
        XCTAssertTrue(pi.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path))
    }

    func testInstallIsIdempotent() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .codex, .grok, .pi])
        let secondReports = try installer.install(targets: [.claude, .codex, .grok, .pi])

        XCTAssertTrue(secondReports.allSatisfy { !$0.changed })
    }

    func testInspectReportsCurrentHooksAfterInstall() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .codex, .grok, .pi])

        let inspection = try installer.inspect()

        XCTAssertTrue(inspection.isCurrent)
        XCTAssertFalse(inspection.needsUpdate)
        XCTAssertEqual(inspection.hookScriptStatus, .current)
        XCTAssertEqual(inspection.currentTargetCount, 4)
        XCTAssertEqual(inspection.installedTargetCount, 4)
        XCTAssertEqual(inspection.targets.map(\.status), [.current, .current, .current, .current])
    }

    func testInspectReportsOutdatedSharedHookScript() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .codex, .grok, .pi])

        let hookScriptURL = home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh")
        try "#!/usr/bin/env bash\n/usr/bin/caffeinate -is -t 600\n".write(
            to: hookScriptURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)

        let inspection = try installer.inspect()

        XCTAssertFalse(inspection.isCurrent)
        XCTAssertTrue(inspection.needsUpdate)
        XCTAssertEqual(inspection.hookScriptStatus, .outdated)
        XCTAssertNotEqual(inspection.expectedHookScriptFingerprint, inspection.installedHookScriptFingerprint)
        XCTAssertEqual(inspection.currentTargetCount, 4)
    }

    func testInstallReportingFailuresMarksTargetsChangedWhenSharedHookScriptUpdates() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .codex, .grok, .pi])

        let hookScriptURL = home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh")
        try "#!/usr/bin/env bash\n/usr/bin/caffeinate -is -t 600\n".write(
            to: hookScriptURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)

        let reports = installer.installReportingFailures(targets: [.claude, .codex, .grok, .pi])

        XCTAssertTrue(reports.allSatisfy(\.succeeded))
        XCTAssertTrue(reports.allSatisfy(\.changed))
        XCTAssertTrue(reports.allSatisfy { $0.message == "shared hook script updated" })
        XCTAssertTrue(try installer.inspect().isCurrent)
    }

    func testInspectReportsOutdatedAgentConfig() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .codex, .grok, .pi])

        let piPath = home.appendingPathComponent(".pi/agent/extensions/dsmn.ts")
        try """
        import { spawn } from "node:child_process";
        spawn("\(home.path)/.dsmn/dsmn-agent-hook.sh", [], {
          env: { DSMN_HOOK_AGENT: "pi" }
        });
        """.write(to: piPath, atomically: true, encoding: .utf8)

        let inspection = try installer.inspect()

        XCTAssertFalse(inspection.isCurrent)
        XCTAssertTrue(inspection.needsUpdate)
        XCTAssertEqual(inspection.hookScriptStatus, .current)
        XCTAssertEqual(inspection.targets.first { $0.target == .pi }?.status, .outdated)
        XCTAssertEqual(inspection.currentTargetCount, 3)
        XCTAssertEqual(inspection.installedTargetCount, 4)
    }

    func testInstallUpdatesDsmnHooksInsideMixedGroupWithoutDroppingUnrelatedHooks() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "hooks": {
            "PostToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "/Users/jb/.claude/hooks/safety.sh" },
                  { "type": "command", "command": "DSMN_HOOK_AGENT='claude' DSMN_HOOK_EVENT='PostToolUse' '\(home.path)/.dsmn/dsmn-agent-hook.sh'" }
                ]
              }
            ]
          }
        }
        """.write(
            to: home.appendingPathComponent(".claude/settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        let reports = try installer.install(targets: [.claude])

        XCTAssertEqual(reports.first?.message, "installed")
        let claude = try readJSON(home.appendingPathComponent(".claude/settings.json"))
        let commands = hookCommands(in: claude)
        XCTAssertTrue(commands.contains("/Users/jb/.claude/hooks/safety.sh"))
        XCTAssertEqual(commands.filter { $0.contains("dsmn-agent-hook.sh") }.count, 4)
    }

    func testInstallReportingFailuresKeepsTargetLevelFailureDetails() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "not a directory".write(
            to: home.appendingPathComponent(".claude"),
            atomically: true,
            encoding: .utf8
        )

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        let reports = installer.installReportingFailures(targets: [.claude, .codex])

        let claude = try XCTUnwrap(reports.first { $0.target == "claude" })
        let codex = try XCTUnwrap(reports.first { $0.target == "codex" })
        XCTAssertFalse(claude.succeeded)
        XCTAssertEqual(claude.message, "failed")
        XCTAssertNotNil(claude.error)
        XCTAssertTrue(codex.succeeded)
    }

    func testHookOmitsEmptyInstallerPathFromCandidates() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "")
        _ = try installer.install(targets: [.codex])

        let hookScript = try String(contentsOf: home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh"), encoding: .utf8)
        XCTAssertFalse(hookScript.contains("''"))
        XCTAssertEqual(
            hookScript.components(separatedBy: "\n").filter { $0.contains("dsmn.app/Contents/Library/Helpers/dsmnctl") }.count,
            2
        )
    }

    func testUninstallRemovesDsmnHooksAndSharedScript() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl")
        _ = try installer.install()

        let reports = try installer.uninstall()
        XCTAssertTrue(reports.contains { $0.target == "hook-script" && $0.changed })
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path))

        let claude = try readJSON(home.appendingPathComponent(".claude/settings.json"))
        XCTAssertTrue(hookCommands(in: claude).filter { $0.contains("dsmn-agent-hook.sh") }.isEmpty)

        let codex = try readJSON(home.appendingPathComponent(".codex/hooks.json"))
        XCTAssertTrue(hookCommands(in: codex).filter { $0.contains("dsmn-agent-hook.sh") }.isEmpty)

        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".grok/hooks/dsmn.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".pi/agent/extensions/dsmn.ts").path))
    }

    func testUninstallPreservesUnrelatedClaudeHooks() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "/Users/jb/.claude/hooks/safety.sh" }
                ]
              }
            ]
          }
        }
        """.write(
            to: home.appendingPathComponent(".claude/settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude])
        _ = try installer.uninstall(targets: [.claude])

        let claude = try readJSON(home.appendingPathComponent(".claude/settings.json"))
        XCTAssertTrue(hookCommands(in: claude).contains("/Users/jb/.claude/hooks/safety.sh"))
        XCTAssertTrue(hookCommands(in: claude).filter { $0.contains("dsmn-agent-hook.sh") }.isEmpty)
    }

    func testUninstallPreservesUnrelatedHooksInsideMixedGroup() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "hooks": {
            "PostToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "/Users/jb/.claude/hooks/safety.sh" },
                  { "type": "command", "command": "DSMN_HOOK_AGENT='claude' DSMN_HOOK_EVENT='PostToolUse' '\(home.path)/.dsmn/dsmn-agent-hook.sh'" }
                ]
              }
            ]
          }
        }
        """.write(
            to: home.appendingPathComponent(".claude/settings.json"),
            atomically: true,
            encoding: .utf8
        )

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        let reports = try installer.uninstall(targets: [.claude])

        XCTAssertEqual(reports.first { $0.target == "claude" }?.message, "removed")
        let claude = try readJSON(home.appendingPathComponent(".claude/settings.json"))
        XCTAssertTrue(hookCommands(in: claude).contains("/Users/jb/.claude/hooks/safety.sh"))
        XCTAssertTrue(hookCommands(in: claude).filter { $0.contains("dsmn-agent-hook.sh") }.isEmpty)
    }

    func testUninstallIsIdempotent() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .codex, .grok, .pi])
        _ = try installer.uninstall()
        let secondReports = try installer.uninstall()

        XCTAssertTrue(secondReports.filter { $0.target != "hook-script" }.allSatisfy { !$0.changed })
        XCTAssertEqual(secondReports.first { $0.target == "hook-script" }?.message, "not present")
    }

    func testPartialUninstallKeepsSharedHookScript() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install()
        _ = try installer.uninstall(targets: [.claude])

        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path))
        XCTAssertTrue(hookCommands(in: try readJSON(home.appendingPathComponent(".codex/hooks.json")))
            .contains { $0.contains("dsmn-agent-hook.sh") })
    }

    func testHookPrefersInstalledAppBeforeInstallerPath() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dev/dsmnctl")
        _ = try installer.install(targets: [.codex])

        let hookScript = try String(contentsOf: home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh"), encoding: .utf8)
        let applicationsRange = try XCTUnwrap(hookScript.range(of: "/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"))
        let homeApplicationsRange = try XCTUnwrap(hookScript.range(of: "$HOME/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl"))
        let installerPathRange = try XCTUnwrap(hookScript.range(of: "/tmp/dev/dsmnctl"))

        XCTAssertFalse(hookScript.contains("NomDeLaSociete"))
        XCTAssertTrue(hookScript.contains("dsmnctl_bundle_version()"))
        XCTAssertTrue(hookScript.contains("version > best_version"))
        XCTAssertLessThan(applicationsRange.lowerBound, installerPathRange.lowerBound)
        XCTAssertLessThan(homeApplicationsRange.lowerBound, installerPathRange.lowerBound)
    }

    func testHookRecordsThrottleStampForFallbackOrConfirmedActiveLock() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dev/dsmnctl")
        _ = try installer.install(targets: [.codex])

        let hookScript = try String(contentsOf: home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh"), encoding: .utf8)
        let fallbackRange = try XCTUnwrap(hookScript.range(of: "fallback_caffeinate()"))
        let fallbackEndRange = try XCTUnwrap(hookScript.range(of: "requester_name()", range: fallbackRange.upperBound..<hookScript.endIndex))
        let fallbackBody = hookScript[fallbackRange.lowerBound..<fallbackEndRange.lowerBound]
        XCTAssertTrue(fallbackBody.contains("record_extend_stamp"))

        let requesterRange = try XCTUnwrap(hookScript.range(of: #"REQUESTER_NAME="$(requester_name)""#))
        let skipRange = try XCTUnwrap(hookScript.range(of: "if should_skip_extend"))
        let resolveRange = try XCTUnwrap(hookScript.range(of: #"ctl="$(resolve_dsmnctl || true)""#))
        let doctorRange = try XCTUnwrap(hookScript.range(of: #"doctor="$("$ctl" doctor 2>&1 || true)""#))
        let localFallbackRange = try XCTUnwrap(hookScript.range(of: #"Status source: local fallback"#))
        let sleepDisabledRange = try XCTUnwrap(hookScript.range(of: #"macOS SleepDisabled: on"#))
        let stampRange = try XCTUnwrap(hookScript.range(of: "record_extend_stamp", options: [], range: sleepDisabledRange.upperBound..<hookScript.endIndex))

        XCTAssertLessThan(requesterRange.lowerBound, skipRange.lowerBound)
        XCTAssertLessThan(skipRange.lowerBound, resolveRange.lowerBound)
        XCTAssertLessThan(doctorRange.lowerBound, localFallbackRange.lowerBound)
        XCTAssertLessThan(localFallbackRange.lowerBound, stampRange.lowerBound)
        XCTAssertLessThan(sleepDisabledRange.lowerBound, stampRange.lowerBound)
    }

    private func temporaryHome() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dsmn-hooks-\(UUID().uuidString)", isDirectory: true)
    }

    private func readJSON(_ path: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: path)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func hookCommands(
        in root: [String: Any],
        events: [String]? = nil
    ) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else {
            return []
        }

        let eventValues: [Any]
        if let events {
            eventValues = events.compactMap { hooks[$0] }
        } else {
            eventValues = Array(hooks.values)
        }

        return eventValues.flatMap { eventValue in
            (eventValue as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                    hook["command"] as? String
                }
            }
        }
    }
}
