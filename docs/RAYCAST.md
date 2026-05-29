# Raycast

The Raycast extension mirrors the Coffee-style workflow:

- set a manual duration;
- toggle auto mode;
- stop everything;
- inspect status;
- optionally expose a Raycast menu bar item.

## Commands

```text
dsmn: Keep Awake For...
dsmn: Toggle Auto Mode
dsmn: Auto On
dsmn: Auto Off
dsmn: Stop
dsmn: Status
dsmn: Menu Bar
```

## Contract

Raycast calls:

```sh
dsmnctl manual --minutes <n>
dsmnctl auto toggle
dsmnctl auto on
dsmnctl auto off
dsmnctl stop
dsmnctl status --json
```

Raycast is not allowed to:

- call `pmset`;
- call `sudo`;
- make power-management decisions itself.

