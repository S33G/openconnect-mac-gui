# Support runbook

1. **Cisco unavailable:** install Cisco through the organization's approved installer or Self Service. Ensure the VPN service is running, then Re-check. Betterer Connect installs nothing and cannot restart services.
2. **No profile or gateway:** enter an IT-provided gateway, or have IT deploy `GatewayList` and `DefaultGateway`. A successful Cisco connection may download its profile. Betterer Connect never modifies Cisco profiles.
3. **Sign-in required:** select Continue in Cisco and complete MFA there. Copy the selected gateway if needed. After three minutes, retry explicitly; an authentication timeout is not retried silently.
4. **Offline:** restore network access. No connection attempts run while the network path is unavailable.
5. **Reconnect stopped:** inspect Cisco, then click Retry connection. The automatic budget is five attempts. Disconnect cancels user intent and queued CLI work.
6. **Signing rejected:** run Cisco directly. A restricted launcher can be rejected by Cisco; a normal app launch may work. Do not change or remove Cisco signatures. Repair the approved installation or consult IT if the problem persists.
7. **Unsupported CLI/state:** use Cisco directly and report the version with a minimal sanitized output shape. Do not send raw transcripts.

Copy diagnostics for the organization's support channel. Review the selected gateway before pasting outside the organization. VPN authentication, policy, posture, or installation issues belong to IT; reproducible Betterer Connect logic/UI issues belong in this project's issue tracker.

Before managed deployment: identify an owner/support contact, review the installed profile's native reconnect/resume and automatic-network policies, complete applicable security/legal review, sign and notarize the app, and qualify it with a small authorized group. None of these rollout steps is implied by a passing local build.
