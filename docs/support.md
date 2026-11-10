# Support runbook

1. **Setup needed:** install `openconnect` and `python@3.11` with Homebrew, then Re-check. openconnect-sso, pipx and Qt are no longer used.
2. **Gateway/group:** use your administrator's DNS hostname and exact authentication group. Group is passed directly to OpenConnect.
3. **Administrator prompt:** enter the Mac password in Terminal. Keep the window open until disconnection. No permanent helper is installed in this development build.
4. **Sign-in:** complete SSO/MFA in your default browser. The gateway must offer native external-browser SSO. Embedded-browser-only SAML requires a gateway configuration change or a different supported client; the app does not scrape or ask you to copy cookies.
5. **Certificate rejected:** confirm the gateway and certificate policy with IT. Do not disable verification.
6. **Offline/reconnect:** restore network access. OpenConnect owns active tunnel recovery; app retries wait for the previous process group to exit. Disconnect cancels retry intent. Settings apply to the next session.
7. **Stale/unconfirmed session:** check the session Terminal. Do not start another VPN over it. Abrupt supervisor/tunnel termination may require manual recovery or restarting the Mac; recovery safely recognizes a new OS boot.

Copy diagnostics for safe dependency/status details. Authentication, device posture, server policy, and gateway compatibility belong to the VPN administrator. Reproducible app lifecycle/UI bugs belong in the issue tracker.

Before distribution, qualify SSO, routing/DNS restoration, dropped tunnels, sleep/wake, cancellation, Terminal closure, forced-crash recovery, MDM preferences, fresh users, both architectures, signing/notarization, and dependency installation.
