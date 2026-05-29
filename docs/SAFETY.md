# Safety Model

The dangerous capability is closed-lid sleep prevention. Regular `caffeinate`
assertions are not sufficient for the clamshell case, so `dsmn` eventually needs
to use `pmset disablesleep`.

That capability is guarded by these rules.

## Ownership

Only `dsmnd` may mutate `pmset`. It records whether it owns the current
`disablesleep` state before attempting cleanup.

During development, `dsmnd` is dry-run by default and does not mark
`ownsSleepDisable` as true unless a non-dry-run `pmset` operation succeeds.

## Release conditions

The helper must release sleep prevention when any hard stop applies:

- manual timer expired;
- auto mode is off and no manual timer is active;
- no supported AI agent is active for the grace period;
- battery is at or below the configured threshold while not on AC power;
- no default network route is available for the configured grace period;
- the lid has been reopened for the configured grace period;
- helper starts and finds stale ownership state from a previous crash;
- user runs stop or repair.

## Defaults

Initial defaults:

- battery stop threshold: 20%;
- no-agent grace: 5 minutes;
- lid-open grace: 5 minutes;
- no-route grace: 15 minutes;
- maximum manual duration: 8 hours.

## Recovery

`dsmnctl repair` will force a cleanup path:

```sh
pmset -a disablesleep 0
```

The command belongs to the helper boundary and must be exposed through a controlled
helper request rather than run by Raycast directly.

## Development guard

`dsmnd` only executes `pmset` when launched with:

```sh
DSMN_APPLY_PMSET=1
```

Raycast and normal CLI workflows should not set this variable.
