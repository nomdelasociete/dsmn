# Raycast

The Raycast extension mirrors the Coffee-style workflow:

- set a manual duration;
- stop everything;
- inspect status;
- optionally expose a Raycast menu bar item.

## Commands

```text
dsmn: Keep Awake For...
dsmn: Stop
dsmn: Status
dsmn: Menu Bar
```

## Contract

Raycast calls:

```sh
dsmnctl manual --minutes <n>
dsmnctl stop
dsmnctl status --json
```

`dsmnctl` tries the privileged helper over XPC first. If the helper is not
registered, it falls back to local development state so the extension remains
usable before installation.

The Xcode app bundle embeds `dsmnctl` at:

```text
Contents/Library/Helpers/dsmnctl
```

The Raycast extension resolves `/Applications/dsmn.app/...` and
`~/Applications/dsmn.app/...` automatically before using development paths.

Raycast is not allowed to:

- call `pmset`;
- call `sudo`;
- make power-management decisions itself.
