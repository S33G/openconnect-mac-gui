# Support runbook

1. **Setup needed:** install `openconnect` and `python@3.11` with Homebrew, then Re-check. No pip or Qt package is needed.
2. **Gateway/group:** use your administrator's DNS hostname and exact authentication group. The field accepts hostnames rather than URL paths or custom ports.
3. **Administrator prompt:** complete sudo authorization in Terminal. In foreground mode, keep Terminal open until disconnection. In background mode, wait for **BACKGROUND READY** before closing it.
4. **Sign-in:** complete SSO/MFA in your default browser. The gateway must offer native external-browser SSO. The app does not scrape browser cookies or ask you to copy tokens.
5. **Certificate rejected:** confirm the gateway and certificate policy with IT. Do not disable verification.
6. **Offline/reconnect:** restore network access. App retries wait for the old process group to exit. Disconnect cancels retry intent. Reconnect/background settings apply to the next session.
7. **Stale/unconfirmed session:** keep the app open and check its safe error code. Do not start another VPN over it. Abrupt supervisor/tunnel termination can require manual recovery or a restart. A fresh OS boot is recognized safely.
8. **Previous build detected:** quit the earlier development app before connecting in the rebranded app. It recovers unfinished sessions in place. Under the new preference identity, re-enter your gateway/group.

A background session still belongs to the menu-bar app. Quit disconnects; it is not a VPN service that survives app exit. See [administrator access](administrator-access.md) for startup authorization options.

Copy diagnostics for safe dependency/status details. Server policy, device posture, and authentication compatibility belong to the VPN administrator; reproducible app problems belong in the project issue tracker. Include dependency versions and a sanitized reproduction, never a real transcript.
