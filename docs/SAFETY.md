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

## Activation model

Sleep prevention is driven by a **manual timer** (`manualUntil`), not by
detected agent processes. Running Claude, Codex, Grok Build, Pi, or Perplexity
Desktop alone does not keep the Mac awake.

Agent hooks call `dsmnctl manual --extend-only` on session and tool events. Each
call renews the current lease up to the configured maximum; renewals are not
additive and never shorten a longer timer already in effect. When tool activity
stops, the timer expires and the helper releases the power lock.

## Release conditions

The helper must release sleep prevention when any hard stop applies:

- manual timer expired;
- no manual timer is active;
- battery is at or below the configured threshold while not on AC power;
- no default network route is available for the configured grace period;
- helper starts and finds stale ownership state from a previous crash;
- user runs stop or repair.

## Defaults

Initial defaults:

- battery stop threshold: 20%;
- lid-open grace: 5 minutes (diagnostic `lid_open_grace` reason only; does not
  release `pmset` while a manual timer is still active);
- no-route grace: 15 minutes;
- maximum manual duration: 8 hours.

## Recovery

`dsmnctl repair` clears stale local state and, when the helper is available,
forces a cleanup path through the privileged helper:

```sh
pmset -a disablesleep 0
```

The helper runs `repair` over XPC: it releases `pmset` when dsmn still owns the
sleep lock, resets persisted state, then reconciles. Raycast and CLI invoke
`dsmnctl repair`; they never call `pmset` directly. Without a registered helper,
`dsmnctl repair` only repairs local state (development fallback).

## XPC client authentication

The privileged helper Mach service `com.nomdelasociete.dsmn.helper` accepts XPC
connections only from code-signed clients that match a designated requirement:

- Apple Development / Developer ID team `JSFMAD28GS`
- bundle identifier `com.nomdelasociete.dsmn` (menu bar app) or
  `com.nomdelasociete.dsmn.dsmnctl` (embedded CLI)

Validation uses the connecting process audit token and `SecCode` (same approach as
Sparkle privileged helpers). Unsigned clients, wrong-team binaries, and unrelated
apps are rejected before any helper method runs. Rejections are logged to helper
stderr and do not stop the listener.

### Threat model

Without authentication, any local process could call `enableManual`, `stop`, or
`reconcile` on the helper and toggle `pmset disablesleep`. That would let
untrusted software keep a Mac awake or fight dsmn ownership state. Requiring a
matching signature ties control to shipped dsmn binaries from the expected team.

This does not protect against a malicious process running with the user's
credentials inside a compromised signed app; it stops drive-by access from random
CLI tools, debug builds, or repackaged unsigned copies.

## Development guard

The one-shot development command only executes `pmset` when launched with:

```sh
DSMN_APPLY_PMSET=1
```

The LaunchDaemon `serve` mode executes power changes only when running as root,
unless forced back to dry-run with `DSMN_APPLY_PMSET=0`. Raycast and normal CLI
workflows should not set these variables.
