# Support runbook

1. **OpenConnect setup needed:** use Install dependencies to copy the tested Homebrew/pipx command. Run it in Terminal, then Re-check. For `pkg_resources` import failures, inject `setuptools<81` into the SSO environment. Python 3.11 is the tested runtime.
2. **Gateway/group:** enter the DNS hostname and exact authentication group from your administrator. Group is passed to openconnect-sso. Defaults and example domains are intentionally empty/non-operational.
3. **Allow the VPN connection:** enter the Mac administrator password into sudo's Terminal prompt. The app cannot enter it. Cancel via Disconnect. Keep Terminal open through teardown.
4. **Finish signing in:** complete the helper's browser SSO/MFA. Sign-in has a three-minute deadline. Authentication failures do not trigger silent retries.
5. **Certificate rejected:** confirm the hostname and certificate policy with IT. Do not disable certificate verification.
6. **Offline/reconnecting:** restore network access. OpenConnect owns native tunnel recovery; app retries wait for the previous group to exit. Disconnect cancels retry intent. Automatic reconnect settings apply to the next session.
7. **Session status stale / disconnect unconfirmed:** check the session Terminal. Do not start another VPN to work around it. The app cannot safely claim teardown while status is unavailable. A forced supervisor/tunnel kill may require manual network recovery or a restart.

Copy diagnostics for safe version/presence/status details. The copy omits gateway, group, and raw authentication output. Authentication, posture, policy, and server compatibility issues belong to the VPN administrator; reproducible app lifecycle/UI bugs belong in the project issue tracker.

Before distribution, qualify sign-in, routing/DNS restoration, dropped tunnels, sleep/wake, Terminal cancellation/closure, fresh accounts, MDM preferences, both architectures, signing/notarization, and dependency installation. Unit tests do not establish those outcomes.
