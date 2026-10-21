# Privacy in dsmn

This describes the app and repository behavior. The
[service privacy notice](https://dsmn.app/legal.html) identifies the controller,
hosting, legal basis, retention, and data-rights contact for dsmn.app.

## On your Mac

dsmn reads power source, battery level, lid state, thermal state, default-route
availability, and running processes to report activity and manage a bounded timer.
Process detection reads executable paths and command arguments. Normal operation
does not upload that process list, but status JSON can contain it.

Agent hooks read a bounded stdin payload to extract agent/event, project basename,
and shortened session context. They do not intentionally save the complete payload.
Context can still identify a private project. It may appear in menus, diagnostics,
and optional feedback.

Local data includes:

| Location | Purpose |
|---|---|
| `/Library/Application Support/dsmn/state.json` | Helper timer, lock ownership, requester and activity/power history |
| `~/.dsmn/state.json` | Local development/fallback state |
| `~/.dsmn/` | Shared hook script, throttle stamp, and lock directory |
| `/tmp/dsmn-agent-hook.log` by default | Hook activity and fallback messages |
| Agent configuration files | Installed dsmn hook entries; see [HOOKS.md](docs/HOOKS.md) |
| App user defaults | Preferences such as durations, countdown, and onboarding |

Environment overrides can change paths. Activity histories have size limits;
some activity is pruned when new events arrive. This is not a guarantee that all
data is deleted after a fixed time. The last requester can remain until replaced
or cleared. Do not assume local files or logs are confidential to the current user.

## Connections to dsmn.app

- **Updates:** configured official builds use Sparkle to check the appcast and
  download updates. Requests expose normal network metadata to the service.
- **Feedback:** only sent when you choose Send. Includes message, category,
  optional email, app version/build, and macOS version even with diagnostics off.
  Diagnostics are off by default; enabling them adds helper/power state, agent
  names, last requester/context, reasons, and error text. Review your message
  and avoid sensitive project/session information.
- **Website/downloads:** the service records first-party page/download/update
  measurements. Its notice currently specifies up to 395 days for measurements
  and 730 days for feedback, subject to the exceptions described there. These
  are service policy statements, not local app deletion guarantees.

No account with dsmn is required. This project does not claim that no data ever
leaves the Mac. Forks or development environment overrides may use other endpoints.

## Sharing and removal

GitHub issues and comments are public. Do not upload unreviewed `status --json`,
doctor output, hook logs, screenshots, or agent configuration. Remove command
arguments, usernames, paths, project/session names, and credentials first.

See [SUPPORT.md](SUPPORT.md) for hook removal and uninstall. Do not delete helper
state while a power lock is active: that state records release responsibility.
For service data access/deletion requests, use the contact in the service notice.
