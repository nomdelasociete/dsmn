# Support and removal

For ordinary bugs, [open an issue](https://github.com/nomdelasociete/dsmn/issues/new/choose)
with reproduction steps, expected/actual behavior, app version/build, and macOS
version. Security reports go [privately](SECURITY.md).

## Check the installed app

Use **Setup & Troubleshooting…** and Doctor. Confirm the installed app and helper
are the versions you intend to test. An available helper update is advisory;
missing registration or approval requires setup/repair.

An active timer is protected when status comes from the helper and the power lock
is on. Local fallback or `caffeinate` does not establish closed-lid protection.
If Stop does not confirm release, keep the app installed and use Repair Helper
or report the failure. Do not erase state to hide the error.

Doctor and logs may include private paths and project/session names. Share a
short redacted excerpt, not entire files. Never attach agent configuration or
credentials. Use invented names in reproductions.

## Remove agent hooks only

Choose **About dsmn → Remove Agent Hooks…**, or run:

```sh
/Applications/dsmn.app/Contents/Library/Helpers/dsmnctl uninstall-hooks all
```

This removes dsmn's hook entries and shared script; it does not stop a running
timer or remove the app/helper. Codex's `features.hooks` setting is intentionally
left in place. A second uninstall should report that entries are absent.

## Uninstall the app

1. Remove agent hooks while the app/CLI is still available, so they cannot renew
   the timer during removal.
2. Choose Stop and confirm the helper power lock is off in Doctor.
3. Turn off launch at login in the app's settings.
4. In **Setup & Troubleshooting…**, use **Unregister Helper**. Resolve any release
   or unregistration failure before continuing. Registration belongs to
   `SMAppService`; do not manually copy or install LaunchDaemon files.
5. Quit dsmn, then remove the app from Applications. Remove its Raycast extension
   separately if installed.

App removal is not a promise to erase all data. After confirming the helper is
unregistered and the lock released, inspect and remove dsmn's residual user state,
hook log, preferences, and helper state if desired; locations are in [PRIVACY.md](PRIVACY.md).
Root-owned helper data requires administrator access. Do not remove entire agent
configuration directories or unrelated hooks. Feedback already sent is handled
through the service privacy contact.
