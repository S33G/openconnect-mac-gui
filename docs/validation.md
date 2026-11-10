# Validation record

OpenConnect Mac GUI 0.4.0, 2026-11-10. Development build; not a notarized public release.

## Automated and local evidence

- 14 Swift tests pass, including configuration/gateway validation, background-off default, retry/stability policy, authentication versus connection, confirmed teardown, stale ownership, certificate failure, and bounded subprocesses.
- 20 Python tests pass. New background coverage includes detached lifetime, foreground-to-background ownership transfer, app-heartbeat loss, cancellation before handoff, symlink-safe status writes, directory anchoring after rename, malformed/FIFO markers, fixed executables, bounded secrets, and nonfatal pinned-certificate warnings.
- The release app builds for Apple Silicon and passes ad-hoc signature verification. OpenConnect and Python are installed separately.
- The rebrand covers the app, bundle identity, executable/module names, icon, notifications, Terminal copy, build/release scripts, CI, and public documentation.
- Public text and the stripped release executable have been scanned for organization branding. Public screenshots contain `vpn.example.com` with no private group. Both native light/dark views were visually inspected.
- The app inherits macOS appearance and accent colors. Preview rendering applies appearance only to its documentation windows; it does not change system settings.
- Independent review checked root input constraints, directory-FD operations, pipe-based ownership transfer, Terminal-close handling, and legacy-session recovery. The new identity blocks connection while the earlier app is running and decodes older requests with background mode absent.

## Live evidence

The preceding native-browser backend completed a real SSO -> configured tunnel -> Disconnect cycle. The app showed Connected, one OpenConnect root process was observed, and Disconnect left zero OpenConnect processes, no session directory, and a physical default route.

The rebranded build was launched and its background controls were inspected. The first live background attempt was closed before a confirmed Connected state; follow-up inspection found no tunnel or detached supervisor. This is cancellation/cleanup evidence, not a successful headless connection.

A subsequent live background session completed default-browser SSO and reached Connected. The privileged OpenConnect process had no controlling terminal, and the app observed a configured tunnel for seven minutes under the detached supervisor. App Disconnect returned the UI to Ready and left zero root OpenConnect processes, zero detached supervisors, no session request, and the physical default route on `en0`.

An intermediate attempt exposed a status-parser bug: a nonfatal certificate warning remained latched after the pinned-certificate tunnel was configured. The parser now clears that warning only on the canonical configured-tunnel event; fatal certificate errors remain failures. A regression test covers this sequence.

Manual closure of the completed startup Terminal window was not confirmed during the successful session. Synthetic tests cover parent exit and app-heartbeat loss; live window-close, app-quit, and route/DNS restoration beyond the default-route check still need qualification.

## Remaining qualification

Internal-service reachability, full split-route/DNS restoration, sleep/wake, interface loss, repeated reconnects, forced-crash recovery, MDM behavior, notification delivery, Intel, and the supported macOS version matrix need further real-host testing.

No persistent privileged helper, PAM change, or sudoers policy is installed. The local keychain check found no stable code-signing identity for helper/distribution work. Developer ID signing, notarization, the installer, and GitHub CI have not been qualified remotely. No repository has been published.
