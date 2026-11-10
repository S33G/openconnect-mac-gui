# Validation record

OpenConnect migration, 2026-11-10. Development build 0.2.0; this replaces the previous Cisco-backend evidence.

## Automated and local evidence

- 13 Swift tests pass: gateway/config validation, retry limits, stable-connection reset, authentication versus tunnel state, confirmed teardown, stale ownership, certificate failure, and bounded subprocess execution.
- 9 Python supervisor tests pass with harmless real child processes: allowlisted status, private configuration, argument validation, interrupt ownership, owner loss, delayed-launch cancellation, cancellation during the administrator stage, terminal failure after spawn, and missing controlling terminal.
- Release app builds for Apple Silicon and passes local ad-hoc signature verification. The app now bundles its own Python supervisor, not VPN dependencies.
- Installed and checked OpenConnect 9.21, openconnect-sso 0.8.1, Python 3.11.18, and setuptools below 81. The SSO CLI starts and its actual argument parser preserves the reconnect timeout. Version 0.8.1 consumes a program-label argument before forwarding options; the launcher accounts for that behavior.
- Actual Qt standard paths resolve into the private session home, not the user's normal browser storage. No credentials were used in this check.
- Native UI launches, detects dependencies, accepts gateway/group settings, and reaches the administrator stage through Terminal. Organization values are local preferences and are not included in source.
- Independent review identified cancellation/recovery gaps and retry-budget reset behavior. Corrections have regression coverage.

## Live and distribution boundaries

A complete authenticated tunnel and disconnect have not yet been verified for this backend. The live handoff reached the administrator stage, then the Mac locked before authentication. The session ended at its deadline and the app removed the completed session directory. A new live test requires the user to unlock the Mac, enter the administrator password, and complete SSO/MFA.

Still to qualify: tunnel routing/DNS restoration, dropped connections, sleep/wake, Terminal closure with an established tunnel, stale recovery under forced process termination, MDM forced preferences, notification delivery, fresh users, Intel, and macOS-version coverage.

The app is not Developer ID signed or notarized. The installer and supplied GitHub CI workflow have not run remotely. No repository has been published.

These are integration/distribution boundaries, not outcomes established by unit tests.
