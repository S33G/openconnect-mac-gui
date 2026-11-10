# Validation record

Native default-browser migration, 2026-11-10. Development version 0.3.0.

## Automated and local evidence

- 13 Swift tests pass: configuration/gateway validation, retries and stable-session reset, authentication versus connection, confirmed teardown, stale ownership, certificate failures, and bounded subprocess execution.
- 12 Python tests pass: native browser arguments, bounded authentication-result parsing, shell-syntax-as-data handling, cookie exclusion from argv, safe environment, allowlisted states, process ownership, owner loss, delayed launch, admin cancellation, terminal failure, and specific-error preservation.
- Release app builds for Apple Silicon and passes ad-hoc signature/bundle verification. OpenConnect and Python are installed independently.
- OpenConnect 9.21 and Python 3.11.18 checked locally. No pip or Qt package is needed by version 0.3.0.
- Reboot recovery uses `kern.bootsessionuuid`, verified available in the normal host runtime. Wall-clock changes do not identify a new boot.
- Independent code reviews checked lifecycle ownership and the two-phase native authentication flow; actionable findings were corrected.

## Live evidence

- A credential-free gateway probe confirmed native external-browser SSO and invoked the browser callback. No authentication URLs or server transcript were persisted.
- The native app launched and retained its existing SwiftUI layout. Gateway and authentication group remained local preferences, outside source control.
- Default-browser SSO completed. The supervisor reported OpenConnect's configured-tunnel message, and the app visibly displayed **You're connected** with elapsed time.
- Process inspection confirmed one OpenConnect tunnel running with root privileges.
- Clicking **Disconnect** returned the UI to **Ready when you are**. Follow-up inspection confirmed zero OpenConnect processes, zero remaining app session directories, and an available default route on the physical network interface.
- The prior Qt helper stalled for this user and is no longer used. Its packages were not uninstalled from the host.

## Remaining qualification

This establishes one real connect/disconnect cycle. It does not establish internal-service reachability, all split routes/DNS restoration, sleep/wake, network loss, repeated reconnects, Terminal closure with a live tunnel, forced-crash recovery, MDM behavior, notification delivery, Intel, or the macOS version matrix.

The app is not Developer ID signed or notarized. No native privileged helper or sudoers modification is installed. The distribution installer and supplied GitHub CI workflow have not run remotely. No repository has been published.
