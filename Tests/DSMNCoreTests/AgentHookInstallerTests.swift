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
        XCTAssertTrue(claudeCommands.contains { $0.contains("caffeinate") })
        let claudeSessionHooks = hookCommands(
            in: claude,
            events: ["SessionStart", "UserPromptSubmit"]
        )
        XCTAssertFalse(claudeSessionHooks.contains { $0.contains("caffeinate") })
        XCTAssertEqual(
            claudeCommands.filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            2
        )
        XCTAssertTrue(claudeCommands.allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='claude'") })

        let codex = try readJSON(home.appendingPathComponent(".codex/hooks.json"))
        XCTAssertEqual(
            hookCommands(in: codex).filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            2
        )
        XCTAssertTrue(hookCommands(in: codex).allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='codex'") })
        let codexConfig = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
        XCTAssertTrue(codexConfig.contains("[features]\nhooks = true"))
        XCTAssertTrue(codexConfig.contains("[desktop]\npreventSleepWhileRunning = true"))

        let grok = try readJSON(home.appendingPathComponent(".grok/hooks/dsmn.json"))
        XCTAssertEqual(
            hookCommands(in: grok).filter { $0.contains(home.appendingPathComponent(".dsmn/dsmn-agent-hook.sh").path) }.count,
            2
        )
        XCTAssertTrue(hookCommands(in: grok).allSatisfy { !$0.contains("dsmn-agent-hook.sh") || $0.contains("DSMN_HOOK_AGENT='grok'") })

        let pi = try String(contentsOf: home.appendingPathComponent(".pi/agent/extensions/dsmn.ts"), encoding: .utf8)
        XCTAssertTrue(pi.contains("from \"@earendil-works/pi-coding-agent\""))
        XCTAssertFalse(pi.contains("pi.on(\"tool_call\""))
        XCTAssertFalse(pi.contains("pi.on(\"turn_start\""))
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
