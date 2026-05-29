# Hooks

Use `dsmnctl` from hooks instead of spawning long stacks of `caffeinate`
processes.

The menu bar app does not need to be open for hooks. The required piece is the
privileged helper registered by `dsmn.app`; `dsmnctl` talks to that helper over
XPC.

## Claude Code

The repo ships a hook wrapper:

```sh
/Users/jb/Documents/Github/NomDeLaSociete/dsmn/scripts/claude-hook.sh
```

Default behavior:

- call `dsmnctl manual --minutes 20`;
- verify that `dsmnctl doctor` sees the helper and `macOS SleepDisabled: on`;
- fall back to `caffeinate -is -t 600` only when `dsmnctl` or the helper are not
  available;
- never use `caffeinate -d`, so the fallback does not intentionally keep the
  display awake.

The manual timer is intentional for hooks: every tool call extends a bounded
lease, and dsmn releases it automatically if tool calls stop.

Optional environment overrides:

```sh
DSMN_HOOK_MODE=auto      # use dsmnctl auto on instead of a manual timer
DSMN_HOOK_MINUTES=30     # manual timer duration
DSMNCTL_PATH=/path/to/dsmnctl
DSMN_HOOK_LOG=/tmp/dsmn-claude-hook.log
```

Claude settings example:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/jb/Documents/Github/NomDeLaSociete/dsmn/scripts/claude-hook.sh"
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
/Users/jb/Documents/Github/NomDeLaSociete/dsmn/dist/export/dsmn.app/Contents/Library/Helpers/dsmnctl doctor
pmset -g live | rg 'SleepDisabled'
tail -n 20 /tmp/dsmn-claude-hook.log
```

Expected while protected:

```text
Power lock: on
macOS SleepDisabled: on
SleepDisabled 1
```
