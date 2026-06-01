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

`stop` intentionally leaves `ownsSleepDisable` set until a subsequent reconcile
has actually run `pmset -a disablesleep 0`. This prevents the app or CLI from
forgetting ownership before the system state has been released.

Quitting the menu bar app is not the same as stopping protection. The app asks
for an explicit choice when dsmn is active: `Stop & Quit` releases the current
timer before closing, while `Quit, Keep Running` leaves the helper and hooks in
their current state.

## Release conditions

The helper must release sleep prevention when any hard stop applies:

- manual timer expired;
- no manual timer is active;
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

The one-shot development command only executes `pmset` when launched with:

```sh
DSMN_APPLY_PMSET=1
```

The LaunchDaemon `serve` mode executes power changes only when running as root,
unless forced back to dry-run with `DSMN_APPLY_PMSET=0`. Raycast and normal CLI
workflows should not set these variables.
