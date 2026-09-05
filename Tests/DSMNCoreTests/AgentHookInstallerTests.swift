import XCTest
import TOMLKit
@testable import DSMNCore

final class AgentHookInstallerTests: XCTestCase {
    func testCodexInstallationPreservesCommentedFeatureHeader() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let config = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = "[features] # valid table comment\nhooks = false # user note\nother = true\n[desktop] # next table\nname = 'original'\n"
        try original.write(to: config, atomically: true, encoding: .utf8)

        _ = try AgentHookInstaller(homeDirectory: home).install(targets: [.codex])

        let installed = try String(contentsOf: config, encoding: .utf8)
        let parsed = try TOMLTable(string: installed)
        XCTAssertEqual(parsed["features"]?.table?["hooks"]?.bool, true)
        XCTAssertEqual(parsed["features"]?.table?["other"]?.bool, true)
        XCTAssertEqual(parsed["desktop"]?.table?["name"]?.string, "original")
        XCTAssertEqual(installed, original.replacingOccurrences(of: "hooks = false", with: "hooks = true"))
    }

    func testCodexPreparationFailurePreservesBothExistingFiles() throws {
        let validJSON = Data("{ \"other\": true, \"hooks\": {} }\n".utf8)
        let validTOML = Data("[features] # keep\nhooks = false\n".utf8)
        let fixtures: [(Data, Data)] = [
            (validJSON, Data("[features]\nhooks = false\n[features]\nhooks = true\n".utf8)),
            (validJSON, Data("secret = 'private-value\n".utf8)),
            (validJSON, Data([0xff, 0xfe])),
            (validJSON, Data("features = { hooks = false }\n".utf8)),
            (validJSON, Data("features.hooks = false\n".utf8)),
            (Data("{ invalid private-value".utf8), validTOML),
            (Data("[]".utf8), validTOML),
            (Data(), validTOML),
            (Data("{\"hooks\": []}".utf8), validTOML),
            (Data("{\"hooks\": {\"PreToolUse\": true}}".utf8), validTOML)
        ]
        for (json, toml) in fixtures {
            let home = temporaryHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let directory = home.appendingPathComponent(".codex")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let jsonPath = directory.appendingPathComponent("hooks.json")
            let tomlPath = directory.appendingPathComponent("config.toml")
            try json.write(to: jsonPath)
            try toml.write(to: tomlPath)

            let report = try XCTUnwrap(AgentHookInstaller(homeDirectory: home).installReportingFailures(targets: [.codex]).first)

            XCTAssertFalse(report.succeeded)
            XCTAssertFalse(report.changed)
            XCTAssertFalse(report.error?.contains("private-value") ?? true)
            XCTAssertTrue(report.error?.contains(directory.path) ?? false)
            XCTAssertEqual(try Data(contentsOf: jsonPath), json)
            XCTAssertEqual(try Data(contentsOf: tomlPath), toml)
        }
    }

    func testCodexUnreadableInputIsNotTreatedAsEmpty() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = directory.appendingPathComponent("hooks.json")
        let toml = directory.appendingPathComponent("config.toml")
        let originalJSON = Data("{ \"keep\": true }\n".utf8)
        let originalTOML = Data("[features]\nhooks = false\n".utf8)
        try originalJSON.write(to: json)
        try originalTOML.write(to: toml)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: toml.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: toml.path) }
        guard !FileManager.default.isReadableFile(atPath: toml.path) else {
            throw XCTSkip("An elevated test runner can read mode-000 files")
        }

        let report = try XCTUnwrap(AgentHookInstaller(homeDirectory: home).installReportingFailures(targets: [.codex]).first)

        XCTAssertFalse(report.succeeded)
        XCTAssertEqual(try Data(contentsOf: json), originalJSON)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: toml.path)
        XCTAssertEqual(try Data(contentsOf: toml), originalTOML)
    }

    func testCodexNonRegularConfigurationIsRefused() throws {
        for useSymlink in [false, true] {
            let home = temporaryHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let directory = home.appendingPathComponent(".codex")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let json = directory.appendingPathComponent("hooks.json")
            let toml = directory.appendingPathComponent("config.toml")
            let external = home.appendingPathComponent("external.toml")
            let original = Data("[features]\nhooks = false\n".utf8)
            try original.write(to: external)
            if useSymlink {
                try FileManager.default.createSymbolicLink(at: toml, withDestinationURL: external)
            } else {
                try FileManager.default.createDirectory(at: toml, withIntermediateDirectories: false)
            }
            try Data("{}".utf8).write(to: json)

            let report = try XCTUnwrap(AgentHookInstaller(homeDirectory: home).installReportingFailures(targets: [.codex]).first)

            XCTAssertFalse(report.succeeded)
            XCTAssertEqual(try Data(contentsOf: json), Data("{}".utf8))
            XCTAssertEqual(try Data(contentsOf: external), original)
        }
    }

    func testCodexDetectedInterveningEditDoesNotReplaceEitherFile() throws {
        for editedName in ["config.toml", "hooks.json"] {
            let home = temporaryHome()
            defer { try? FileManager.default.removeItem(at: home) }
            let directory = home.appendingPathComponent(".codex")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let json = directory.appendingPathComponent("hooks.json")
            let toml = directory.appendingPathComponent("config.toml")
            let originalJSON = Data("{}".utf8)
            let originalTOML = Data("[features]\nhooks = false\n".utf8)
            let concurrent = Data((editedName == "config.toml" ? "features.hooks = true\n" : "{\"user_edit\": true}").utf8)
            try originalJSON.write(to: json)
            try originalTOML.write(to: toml)
            var installer = AgentHookInstaller(homeDirectory: home)
            installer.beforeCodexReplacement = { path in
                if path.lastPathComponent == "config.toml" {
                    try concurrent.write(to: directory.appendingPathComponent(editedName))
                }
            }

            let report = try XCTUnwrap(installer.installReportingFailures(targets: [.codex]).first)

            XCTAssertFalse(report.succeeded)
            XCTAssertFalse(report.changed)
            XCTAssertTrue(report.error?.contains("changed during installation") ?? false)
            XCTAssertEqual(try Data(contentsOf: json), editedName == "hooks.json" ? concurrent : originalJSON)
            XCTAssertEqual(try Data(contentsOf: toml), editedName == "config.toml" ? concurrent : originalTOML)
        }
    }

    func testCodexPartialReplacementReportsProgressAndRerunPreservesUserEdit() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = directory.appendingPathComponent("hooks.json")
        let toml = directory.appendingPathComponent("config.toml")
        try Data("{}".utf8).write(to: json)
        try Data("[features]\nhooks = false\n".utf8).write(to: toml)
        let concurrent = Data("{ \"user_edit\": true }".utf8)
        var installer = AgentHookInstaller(homeDirectory: home)
        installer.beforeCodexReplacement = { path in
            if path.lastPathComponent == "hooks.json" { try concurrent.write(to: path) }
        }

        let report = try XCTUnwrap(installer.installReportingFailures(targets: [.codex]).first)

        XCTAssertFalse(report.succeeded)
        XCTAssertTrue(report.changed)
        XCTAssertEqual(report.message, "partially installed")
        XCTAssertTrue(report.error?.contains("config.toml was updated") ?? false)
        XCTAssertTrue(try CodexFeatureConfiguration.hooksEnabled(in: String(contentsOf: toml, encoding: .utf8)))
        XCTAssertEqual(try Data(contentsOf: json), concurrent)
        installer.beforeCodexReplacement = nil
        XCTAssertTrue(try XCTUnwrap(installer.install(targets: [.codex]).first).succeeded)
        XCTAssertEqual(try readJSON(json)["user_edit"] as? Bool, true)
        XCTAssertFalse(try XCTUnwrap(installer.install(targets: [.codex]).first).changed)
    }

    func testCodexPermissionsAndExactBytesSurviveIdempotentInstallAndUninstall() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = directory.appendingPathComponent("hooks.json")
        let toml = directory.appendingPathComponent("config.toml")
        try Data("{}".utf8).write(to: json)
        try Data("[features] # keep\r\n'hooks' = false # keep\r\n".utf8).write(to: toml)
        for path in [json, toml] {
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: path.path)
        }
        let installer = AgentHookInstaller(homeDirectory: home)
        _ = try installer.install(targets: [.codex])
        // Deliberately use a different valid JSON spelling after hooks are current.
        let compactJSON = try JSONSerialization.data(withJSONObject: readJSON(json), options: [.sortedKeys])
        try compactJSON.write(to: json)
        let featureBytes = try Data(contentsOf: toml)
        let jsonAttributes = try FileManager.default.attributesOfItem(atPath: json.path)
        let tomlAttributes = try FileManager.default.attributesOfItem(atPath: toml.path)

        XCTAssertFalse(try XCTUnwrap(installer.install(targets: [.codex]).first).changed)

        XCTAssertEqual(try Data(contentsOf: json), compactJSON)
        XCTAssertEqual(try Data(contentsOf: toml), featureBytes)
        for (path, attributes) in [(json, jsonAttributes), (toml, tomlAttributes)] {
            let current = try FileManager.default.attributesOfItem(atPath: path.path)
            XCTAssertEqual(current[.posixPermissions] as? NSNumber, 0o640)
            XCTAssertEqual(current[.systemFileNumber] as? NSNumber, attributes[.systemFileNumber] as? NSNumber)
        }
        _ = try installer.uninstall(targets: [.codex])
        XCTAssertFalse(try XCTUnwrap(installer.uninstall(targets: [.codex]).first).changed)
        XCTAssertEqual(try Data(contentsOf: toml), featureBytes)
    }

    func testCodexInspectionRequiresValidEnabledFeatureFlag() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let installer = AgentHookInstaller(homeDirectory: home)
        _ = try installer.install(targets: [.codex])
        let toml = home.appendingPathComponent(".codex/config.toml")
        for text in ["", "[features]\nhooks = false\n", "[desktop]\nname = 'keep'\n"] {
            try text.write(to: toml, atomically: true, encoding: .utf8)
            XCTAssertEqual(try installer.inspect(targets: [.codex]).targets.first?.status, .outdated)
        }
        try FileManager.default.removeItem(at: toml)
        XCTAssertFalse(try installer.inspect(targets: [.codex]).isCurrent)
        for text in ["features.hooks = true\n", "features = { hooks = true }\n"] {
            try text.write(to: toml, atomically: true, encoding: .utf8)
            XCTAssertTrue(try installer.inspect(targets: [.codex]).isCurrent)
        }
        try "[features]\nhooks = false\n[features]\nhooks = true\n".write(to: toml, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try installer.inspect(targets: [.codex]))
    }

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

        XCTAssertEqual(Set(reports.map(\.target)), Set(["claude", "cursor", "codex", "grok", "pi"]))
        let hookScriptURL = home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hookScriptURL.path))
        let hookScript = try String(contentsOf: hookScriptURL, encoding: .utf8)
        XCTAssertTrue(hookScript.contains(#"manual_args=(manual --minutes "$MINUTES" --extend-only --requester "$REQUESTER_NAME" --json)"#))
        XCTAssertTrue(hookScript.contains("MIN_INTERVAL_SECONDS=\"${DSMN_HOOK_MIN_INTERVAL_SECONDS:-120}\""))
        XCTAssertTrue(hookScript.contains("should_skip_extend"))
        XCTAssertTrue(hookScript.contains("record_extend_stamp"))
        XCTAssertTrue(hookScript.contains(#"cursor)"#))
        XCTAssertTrue(hookScript.contains("Cursor"))

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

        let cursor = try readJSON(home.appendingPathComponent(".cursor/hooks.json"))
        let cursorVersion = (cursor["version"] as? NSNumber)?.intValue ?? (cursor["version"] as? Int) ?? 0
        XCTAssertEqual(cursorVersion, 1)
        XCTAssertEqual(
            hookCommands(
                in: cursor,
                events: ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse"]
            ).filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            4
        )
        XCTAssertTrue(hookCommands(in: cursor).allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='cursor'") })

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
        _ = try installer.install(targets: [.claude, .cursor, .codex, .grok, .pi])
        let secondReports = try installer.install(targets: [.claude, .cursor, .codex, .grok, .pi])

        XCTAssertTrue(secondReports.allSatisfy { !$0.changed })
    }

    func testInstallPreservesExistingCursorHooks() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".cursor", isDirectory: true),
            withIntermediateDirectories: true
        )
        try """
        {
          "version": 1,
          "hooks": {
            "afterFileEdit": [
              { "command": "./hooks/format.sh" }
            ]
          }
        }
        """.write(
            to: home.appendingPathComponent(".cursor/hooks.json"),
            atomically: true,
            encoding: .utf8
        )

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        let reports = try installer.install(targets: [.cursor])

        XCTAssertEqual(reports.first?.message, "installed")
        let cursor = try readJSON(home.appendingPathComponent(".cursor/hooks.json"))
        XCTAssertTrue(hookCommands(in: cursor, events: ["afterFileEdit"]).contains("./hooks/format.sh"))
        XCTAssertEqual(
            hookCommands(
                in: cursor,
                events: ["sessionStart", "beforeSubmitPrompt", "preToolUse", "postToolUse"]
            ).filter { $0.contains("dsmn-agent-hook.sh") }.count,
            4
        )

        _ = try installer.uninstall(targets: [.cursor])
        let afterUninstall = try readJSON(home.appendingPathComponent(".cursor/hooks.json"))
        XCTAssertTrue(hookCommands(in: afterUninstall, events: ["afterFileEdit"]).contains("./hooks/format.sh"))
        XCTAssertTrue(hookCommands(in: afterUninstall).filter { $0.contains("dsmn-agent-hook.sh") }.isEmpty)
    }

    func testInspectReportsCurrentHooksAfterInstall() throws {
        let home = temporaryHome()
        defer {
            try? FileManager.default.removeItem(at: home)
        }

        let installer = AgentHookInstaller(homeDirectory: home, dsmnctlPath: "/tmp/dsmnctl")
        _ = try installer.install(targets: [.claude, .cursor, .codex, .grok, .pi])

        let inspection = try installer.inspect()

        XCTAssertTrue(inspection.isCurrent)
        XCTAssertFalse(inspection.needsUpdate)
        XCTAssertEqual(inspection.hookScriptStatus, .current)
        XCTAssertEqual(inspection.currentTargetCount, 5)
        XCTAssertEqual(inspection.installedTargetCount, 5)
        XCTAssertEqual(inspection.targets.map(\.status), [.current, .current, .current, .current, .current])
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
        _ = try installer.install(targets: [.claude, .cursor, .codex, .grok, .pi])

        let hookScriptURL = home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh")
        try "#!/usr/bin/env bash\n/usr/bin/caffeinate -is -t 600\n".write(
            to: hookScriptURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)

        let reports = installer.installReportingFailures(targets: [.claude, .cursor, .codex, .grok, .pi])

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
        XCTAssertTrue(hookCommands(in: try readJSON(home.appendingPathComponent(".cursor/hooks.json")))
            .filter { $0.contains("dsmn-agent-hook.sh") }.isEmpty)
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
        XCTAssertTrue(hookScript.contains(#"LOCK_PATH="${DSMN_HOOK_LOCK:-$HOME/.dsmn/extend.lock}""#))
        XCTAssertTrue(hookScript.contains("acquire_extend_lock()"))
        XCTAssertTrue(hookScript.contains("extend lock busy; skipping"))

        let fallbackRange = try XCTUnwrap(hookScript.range(of: "fallback_caffeinate()"))
        let fallbackEndRange = try XCTUnwrap(hookScript.range(of: "requester_name()", range: fallbackRange.upperBound..<hookScript.endIndex))
        let fallbackBody = hookScript[fallbackRange.lowerBound..<fallbackEndRange.lowerBound]
        XCTAssertTrue(fallbackBody.contains("record_extend_stamp"))

        let requesterRange = try XCTUnwrap(hookScript.range(of: #"REQUESTER_NAME="$(requester_name)""#))
        let lockRange = try XCTUnwrap(hookScript.range(of: "acquire_extend_lock", options: [], range: requesterRange.upperBound..<hookScript.endIndex))
        let skipRange = try XCTUnwrap(hookScript.range(of: "if should_skip_extend"))
        let resolveRange = try XCTUnwrap(hookScript.range(of: #"ctl="$(resolve_dsmnctl || true)""#))
        let doctorRange = try XCTUnwrap(hookScript.range(of: #"doctor="$("$ctl" doctor 2>&1 || true)""#))
        let localFallbackRange = try XCTUnwrap(hookScript.range(of: #"Status source: local fallback"#))
        let sleepDisabledRange = try XCTUnwrap(hookScript.range(of: #"macOS SleepDisabled: on"#))
        let stampRange = try XCTUnwrap(hookScript.range(of: "record_extend_stamp", options: [], range: sleepDisabledRange.upperBound..<hookScript.endIndex))

        XCTAssertLessThan(requesterRange.lowerBound, skipRange.lowerBound)
        XCTAssertLessThan(lockRange.lowerBound, skipRange.lowerBound)
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
                let nested = (group["hooks"] as? [[String: Any]] ?? []).compactMap { hook in
                    hook["command"] as? String
                }
                if let command = group["command"] as? String {
                    return nested + [command]
                }
                return nested
            }
        }
    }
}
