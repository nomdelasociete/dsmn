# Hooks

Use `dsmnctl` from hooks instead of spawning long stacks of `caffeinate`
processes. The hook is agent-agnostic: Claude Code, Cursor, Codex, Grok Build, Pi, or
any future tool should call the same `dsmn-agent-hook.sh` contract.

The menu bar app does not need to be open for hooks. The required piece is the
privileged helper registered by `dsmn.app`; `dsmnctl` talks to that helper over
XPC.

## Install

dsmn can install the hook automatically:

```sh
/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl install-hooks
```

Or from a local build:

```sh
dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl install-hooks
./scripts/install-agent-hooks.sh
```

Supported targets:

```sh
dsmnctl install-hooks all
dsmnctl install-hooks claude
dsmnctl install-hooks cursor
dsmnctl install-hooks codex
dsmnctl install-hooks grok
dsmnctl install-hooks pi
```

The installer writes the executable hook to:

```text
~/.dsmn/dsmn-agent-hook.sh
```

Re-run `dsmnctl install-hooks` after upgrading dsmn so `~/.dsmn/dsmn-agent-hook.sh`
is regenerated. Older installs may still contain developer-only `dsmnctl` search
paths that are no longer shipped.

Then it installs:

- Claude Code: `~/.claude/settings.json`
- Cursor: `~/.cursor/hooks.json`
- Codex: `~/.codex/hooks.json`
- Grok Build: `~/.grok/hooks/dsmn.json`
- Pi: `~/.pi/agent/extensions/dsmn.ts`

Cursor hooks use Cursor's native `hooks.json` schema (`version` plus per-event
`command` entries) on `sessionStart`, `beforeSubmitPrompt`, `preToolUse`, and
`postToolUse`. Install merges dsmn into an existing user hooks file and leaves
unrelated commands in place. Tab completion hooks are not installed.

Grok Bot cloud work runs on Grok's computer and does not need the Mac to stay
awake. Using Grok inside Cursor Agent is covered by the Cursor hooks. Grok Bot
local-computer commands, when enabled, are also covered if they run through
Cursor's agent hook path. Grok Build remains the CLI/`~/.grok` target.

For Codex, it also makes sure the current `features.hooks` flag is enabled in
`~/.codex/config.toml`.

For Pi, dsmn installs a native TypeScript extension in Pi's global extension
directory. Existing Pi sessions may need `/reload` or a restart before they
pick up the extension.

## Uninstall

Remove dsmn hook entries without touching unrelated agent configuration:

```sh
dsmnctl uninstall-hooks
dsmnctl uninstall-hooks claude
dsmnctl uninstall-hooks all --json
```

`uninstall-hooks` with no target or `all` removes Claude, Cursor, Codex, Grok, and Pi
entries and deletes `~/.dsmn/dsmn-agent-hook.sh`. A partial target uninstall
leaves the shared script in place for the remaining agents.

The menu bar app exposes the same full uninstall from **About dsmn → Remove
Agent Hooks…** (with confirmation). That does not quit dsmn or stop an active
manual timer.

Re-run `dsmnctl install-hooks` to restore hooks after uninstalling.

## Behavior

- run on session start, user prompt submit, pre-tool-use, and post-tool-use
  events where the agent supports them;
- for Cursor, run on `sessionStart`, `beforeSubmitPrompt`, `preToolUse`, and
  `postToolUse`;
- for Cursor, run on `sessionStart`, `beforeSubmitPrompt`, `preToolUse`, and
  `postToolUse`;
  `tool_result`, and `turn_end`;
- skip `dsmnctl manual` when the last successful extend was within the minimum
  interval (default 120 seconds), using a stamp file at
  `~/.dsmn/last-extend.stamp`;
- call `dsmnctl manual --minutes 20 --extend-only --requester <agent>` when not
  throttled;
- record the last requester and a short recent-requester list in dsmn state,
  with project/session context when the hook payload exposes it;
- verify that `dsmnctl doctor` sees the helper and `macOS SleepDisabled: on`;
- fall back to `caffeinate -is -t 600` only when `dsmnctl` or the helper are not
  available;
- never use `caffeinate -d`, so the fallback does not intentionally keep the
  display awake.

### Fallback caffeinate and clamshell mode

When `dsmnctl` or the privileged helper is unavailable, the hook logs
`fallback caffeinate started` and runs `caffeinate -is -t 600` (or
`DSMN_HOOK_FALLBACK_SECONDS`) instead of renewing a dsmn manual timer.

That fallback only prevents idle system sleep while the Mac is awake with the
lid open. It does **not** apply dsmn's macOS power lock, so **closed-lid /
clamshell protection is not available** during fallback. A MacBook can still
sleep with the lid closed even while agent work continues.

`dsmnctl doctor` and the menu bar app read `DSMN_HOOK_LOG` (default
`/tmp/dsmn-agent-hook.log`) and warn when a fallback event is still inside the
fallback window. Normal protected state shows `Hook fallback: inactive`,
`Status source: helper`, and `Power lock: on`.

The manual timer is intentional for hooks: agent activity renews a bounded
lease, but the shared hook throttles the actual `dsmnctl manual` calls so
tool-heavy sessions do not invoke dsmnctl for every tool event. Hook renewals
are not additive and never shorten a longer manual timer; dsmn releases the
lease automatically when activity stops.

The helper's release deadline uses persisted lease intent independently of
optional process and system diagnostics. A slow or failed probe cannot extend a
hook lease or block its cleanup attempt. Unknown network data preserves an
already recorded no-route deadline. Failed power releases retain ownership and
retry; a bounded attempt does not guarantee that macOS accepted the release.
Hook events, renewal throttling, and the manual-command timeout are unchanged.

Optional environment overrides:

```sh
DSMN_HOOK_MINUTES=30                  # manual timer duration
DSMN_HOOK_MIN_INTERVAL_SECONDS=120    # minimum seconds between dsmnctl manual calls
DSMNCTL_PATH=/path/to/dsmnctl
DSMN_HOOK_LOG=/tmp/dsmn-agent-hook.log
DSMN_HOOK_STAMP=~/.dsmn/last-extend.stamp
```

Manual hook JSON example:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "DSMN_HOOK_AGENT='codex' DSMN_HOOK_EVENT='PreToolUse' '/Users/jb/.dsmn/dsmn-agent-hook.sh'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Verification

After a hook fires:

```sh
dsmnctl doctor
pmset -g live | rg 'SleepDisabled'
tail -n 20 /tmp/dsmn-agent-hook.log
```

Expected while protected:

```text
Hook fallback: inactive
Status source: helper
Power lock: on
macOS SleepDisabled: on
SleepDisabled 1
```

If the hook log shows a recent `fallback caffeinate started` line, `doctor`
prints `Hook fallback: active` and a warning that closed-lid sleep prevention
is unavailable until the helper path is restored.

Throttled invocations log a line like `dsmn extend throttled` and exit without
calling `dsmnctl manual` again.
