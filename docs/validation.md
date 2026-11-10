# Validation record

Local development validation, 2026-11-10. This is not a signed/notarized release or an organization-wide qualification.

## Automated evidence

- 30 Swift unit/component tests pass and exercise exact state parsing, Cisco's zero-exit-code GUI-ownership error, alias-only host lists, safe diagnostics fields, gateway validation, empty config, retry limits/jitter/reset, terminal error latching, SSO timeout/success, offline/manual-disconnect behavior, managed reconnect updates, and safe XML parsing.
- Process tests run real harmless child processes to check literal argument handling, closed stdin, timeouts, output bounds, missing executables, and cancellation of active/queued commands.
- Release app compiles for Apple Silicon, with a macOS 13.0 minimum deployment target.
- Local ad-hoc signature and bundle plist checked. App bundle payload contains only Betterer Connect and its own icon/metadata. The notarized installer has not been produced.
- The GitHub workflow is supplied but has not run remotely. Intel/macOS-version matrix and MDM behavior have not been exercised on real managed devices.

## Live evidence

Test machine: Cisco Secure Client 5.1.20.333. No private gateway names or raw transcripts are included here.

- Read-only `state` and `hosts` commands succeed outside the development sandbox. The restricted tool environment produces a Cisco code-signing rejection; this is kept distinct from the normal app launch.
- Native app launches, detects Cisco and the running agent, discovers installed-profile gateways, and shows Disconnected correctly.
- Connect while Cisco UI owns control initially exposed an unrecognized error with exit status 0. Added a parser regression and fixed the app to hand off instead of timing out/retrying.
- Retest visibly reached **Finish signing in** in Betterer Connect and opened Cisco. Cisco's own Connect reached its browser-authentication prompt.
- Disconnect stops the app's pending retry intent. The three-minute SSO timeout was observed; the pending sign-in was cancelled in Cisco and Cisco returned to Ready to connect. A fully authenticated Connected → Disconnect cycle remains unverified.
- App/window layout inspected through macOS accessibility and a screenshot. Public screenshots should use `--demo` so no real gateway appears.

## Remaining qualification

- Complete MFA, confirm Connected from CLI and app, verify the selected gateway preference, then verify actual disconnection.
- Sleep/wake, interface loss/regain, and a dropped tunnel with both valid and expired SSO sessions.
- Missing-Cisco install/recovery UX on a separate machine. Do not rename or disable a production Cisco installation to test this.
- Notifications permission/delivery on a properly identified distribution build. The local ad-hoc build's permission request failed; inline status continues to work.
- Real MDM forced preferences, client/profile variants, read-only stats formats, fresh user accounts, and Intel architecture.
- Developer ID signing, hardened-runtime distribution execution, notarization, installer validation, and applicable organizational review.

These are integration/distribution gates, not claims covered by unit tests.
