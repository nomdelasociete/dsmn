# Security

Report vulnerabilities through GitHub's
[Report a vulnerability](https://github.com/nomdelasociete/dsmn/security/advisories/new)
or email **contact@nomdelasociete.com**. Do not open a public issue with sensitive
details. If GitHub reporting is unavailable, use email.

Describe the affected version/build, macOS version, reproduction steps, and
impact. Use synthetic examples; do not send private keys, real agent transcripts,
or unrelated personal data. We can agree on a private channel for further evidence.

We aim to acknowledge reports within five business days. This is a target, not
a guaranteed response time. Coordinate publication with the maintainers while a
fix is prepared; reporter credit is optional.

Security fixes target the latest official release. Older versions should update;
there is no maintained backport branch. Include both app and helper versions when
they differ.

The security boundary includes the privileged helper, authenticated XPC clients,
state files, hooks, diagnostics, and update distribution. See the
[safety model](docs/SAFETY.md). A signed CLI is callable by local programs:
code-signature checks are not a claim that each command came from a human click.
