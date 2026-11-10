# Betterer Connect

A native macOS menu-bar app for **OpenConnect**, with SSO in your default browser. Remember your gateway, complete your usual browser sign-in, and see connection status in a small SwiftUI window.

Independent, MIT-licensed project. No employer branding, bundled VPN client, telemetry, or account service. Neither Cisco Secure Client nor openconnect-sso is used or required.

**Status:** development build 0.3.0. Local builds are ad-hoc signed. Real tunnel and distribution qualification are tracked in [validation](docs/validation.md).

## Install and build

Requires macOS 13+, Homebrew, and a gateway that supports `single-sign-on-external-browser` authentication. OpenConnect 9.21 is the locally checked version. Python runs a small standard-library supervisor; it opens no login window and needs no pip packages.

```sh
brew install openconnect python@3.11
```

To build from source, use Xcode with Swift 6+:

```sh
swift test --disable-sandbox
python3 -m unittest discover -s Tests/SessionBridgeTests -v
scripts/build-app.sh
open 'dist/Betterer Connect.app'
```

The app detects Homebrew in `/opt/homebrew` or `/usr/local`, preferring Python 3.11 when installed. A newer Homebrew `python3` also works. Tests use synthetic data and harmless subprocesses; no VPN account or administrator access is needed.

## Connect

1. Open the menu-bar shield. Add your VPN hostname and authentication group.
2. Click **Connect** and complete the normal Mac administrator prompt in Terminal.
3. Sign in through your default browser. Existing browser SSO sessions can be reused. The app reports Connected after OpenConnect reports a configured tunnel.
4. **Disconnect** stops that session. Keep Terminal open until teardown finishes. Quit also requests disconnection.

Authentication uses OpenConnect's documented [two-phase flow](https://www.infradead.org/openconnect/manual.html): authenticate as the logged-in user with `--external-browser=/usr/bin/open`, then create the tunnel with administrator privileges. The short-lived cookie crosses an in-memory pipe; it is never copied to the clipboard, persisted, printed to Terminal, or placed in a command argument. The app never asks for a VPN password.

The current development build uses `sudo` in Terminal. A native privileged helper with one-time macOS approval is a possible future integration; no helper or sudoers change is installed by this version.

**Reconnect automatically** lets OpenConnect restore an active tunnel for up to 300 seconds. After an established session exits, the app can make five further attempts with bounded backoff. The budget resets after 30 seconds of confirmed connection. Authentication, certificate, and permission failures require explicit retry. Change this setting while disconnected; when off, OpenConnect's recovery window is one second. App launch never initiates a new VPN connection.

For a generic UI preview, quit the running app, then run:

```sh
open 'dist/Betterer Connect.app' --args --demo --show-window
```

## Configuration

Preference domain: `io.github.bettererconnect`. Public defaults contain no organizational values. [Managed preference template](Packaging/managed-preferences.plist) is an MDM custom-settings example, not a signed mobileconfig.

| Key | Type | Default |
| --- | --- | --- |
| `GatewayList` | array of DNS hostnames | empty |
| `DefaultGateway` | DNS hostname | empty |
| `PreferredGroup` | authentication group passed to OpenConnect | empty |
| `AutoReconnect` | boolean | true |
| `MaxBackoffSeconds` | retry delay cap, 2–3600 | 300 |
| `SupportChannel` | optional support label | empty |

Managed values take precedence. Forced group/reconnect values lock their controls. Gateway selection and last successfully used gateway are remembered separately. Hostnames only: ports, URL paths, and user-group URL suffixes are not currently supported in the gateway field.

## Lifecycle and limits

SwiftUI provides the menu/window; pure Swift code owns connection intent and retries. An unprivileged Python supervisor launches owned process groups, parses bounded output into safe states, and monitors the app heartbeat. A separate standard-library authentication adapter captures OpenConnect's authentication result as data, never as an evaluated shell script.

Private mode-0700 session folders under `~/Library/Application Support/Betterer Connect/Sessions` contain non-secret launch settings and lifecycle markers. They are removed after confirmed teardown. Only owned process groups are interrupted. A stale supervisor blocks another connection. Startup stops an unfinished prior session; sessions from an earlier OS boot can safely be retired using macOS's stable boot-session UUID.

Browser cookies and sign-in history remain under your normal browser's controls. The app does not inspect them. Normal OpenConnect certificate verification stays enabled. Routing and DNS remain the responsibility of the installed OpenConnect vpnc-script. No custom root scripts, inherited disconnect hooks, root helper, sudoers edits, login item, updater, or telemetry are supplied.

- The gateway must support native external-browser SSO. Embedded-browser-only SAML gateways are not supported by this version.
- Status comes from OpenConnect and supervisor health, not an internal-service reachability probe.
- Only app-owned VPN sessions are tracked. Do not run competing VPN tunnels simultaneously.
- Forced process termination, Terminal closure, and system shutdown need real-host qualification. Uncertain teardown remains an error rather than a false success.
- OpenConnect is installed separately under its own license; no third-party VPN binaries are redistributed here.

## Distribution

Supply your own Developer ID identities and notarytool profile for `scripts/package-release.sh`:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
INSTALLER_IDENTITY='Developer ID Installer: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' \
scripts/package-release.sh
```

The script signs, notarizes/staples, and packages the app. Dependencies require separate installation. Builds target the current Mac architecture; Intel and hardened-runtime execution need separate qualification. See [support](docs/support.md), [security](SECURITY.md), [contributing](CONTRIBUTING.md), and [validation](docs/validation.md).
