# Betterer Connect

A native macOS menu-bar app for **OpenConnect + openconnect-sso**. Remember your gateway, complete browser SSO, and see clear connection status in a small SwiftUI window.

Independent, MIT-licensed project. No employer branding, bundled VPN client, telemetry, or account service. Cisco Secure Client is not used or required.

**Status:** early development build, version 0.2.0. Local builds are ad-hoc signed. Full tunnel, sleep/wake, and distribution qualification are tracked in [validation](docs/validation.md).

## Install dependencies

Requires Homebrew and macOS 13 or newer. The tested SSO helper is 0.8.1; its older dependencies need Python 3.11 and setuptools below 81:

```sh
brew install openconnect pipx python@3.11
pipx install --python "$(brew --prefix python@3.11)/bin/python3.11" 'openconnect-sso==0.8.1'
pipx inject --force openconnect-sso 'setuptools<81'
```

Already installed it with a different Python? Use `pipx reinstall --python "$(brew --prefix python@3.11)/bin/python3.11" openconnect-sso`, then repeat the setuptools injection. The app detects Homebrew in `/opt/homebrew` or `/usr/local` and pipx's launcher in `~/.local/bin`.

[openconnect-sso](https://github.com/vlaci/openconnect-sso) supplies its own Qt browser. It is intended for SAML authentication with compatible VPN gateways; gateway policy and identity-provider support vary. [OpenConnect](https://www.infradead.org/openconnect/manual.html) creates the tunnel and manages routes/DNS through its installed vpnc-script.

## Build and run

Requires Xcode with Swift 6 or newer. Tests do not need a VPN account or administrator access.

```sh
swift test --disable-sandbox
python3 -m unittest discover -s Tests/SessionBridgeTests -v
scripts/build-app.sh
open 'dist/Betterer Connect.app'
```

1. Open the shield in the menu bar. Add your VPN gateway hostname and authentication group.
2. Click **Connect**. Terminal opens for the normal `sudo` administrator prompt. Enter your Mac password there.
3. Complete your organization's sign-in and MFA in the browser opened by openconnect-sso. The app reports Connected only after OpenConnect reports a configured tunnel.
4. Click **Disconnect** to stop that session. Keep Terminal open until teardown completes. Quit also requests disconnection.

No username is passed with `--user`: upstream enables password/TOTP collection and keyring storage in that mode. The app uses visible browser sign-in, disables upstream autofill rules, and supplies a fresh private configuration for each session. It never requests your VPN password itself.

**Reconnect automatically** allows OpenConnect up to 300 seconds to restore an active tunnel. After an established tunnel exits, the app can make up to five further attempts with bounded backoff. The budget resets after 30 seconds of confirmed connection. Authentication, permission, and certificate failures require an explicit retry. Launching the app never starts a new tunnel automatically. Change the reconnect setting while disconnected; with it off, OpenConnect's reconnect window is one second.

To preview the interface with a generic gateway, quit any running instance and use:

```sh
open 'dist/Betterer Connect.app' --args --demo --show-window
```

## Configuration

Preference domain: `io.github.bettererconnect`. No organizational gateways are included. [Managed preference template](Packaging/managed-preferences.plist) is a custom-settings payload example, not a signed mobileconfig.

| Key | Type | Default |
| --- | --- | --- |
| `GatewayList` | array of DNS hostnames | empty |
| `DefaultGateway` | DNS hostname | empty |
| `PreferredGroup` | authentication group passed to SSO | empty |
| `AutoReconnect` | boolean | true |
| `MaxBackoffSeconds` | retry delay cap, 2–3600 | 300 |
| `SupportChannel` | optional support label | empty |

Managed values take precedence. Forced group and reconnect preferences lock their controls. Gateway selection and the last successfully used gateway are remembered separately. A default gateway takes precedence on startup; users can select another for the session. Hostnames only: ports, URL paths, and user-group URL suffixes are not currently supported.

## Architecture and lifecycle

- `BetterConnectCore`: validated configuration and pure lifecycle/retry logic.
- `BettererConnect`: unchanged SwiftUI menu/window layout, preferences, network monitoring, Terminal launch, and safe session-status polling.
- `Resources/session_bridge.py`: an unprivileged Python 3.11+ supervisor. It runs `sudo -v`, then the installed SSO helper, in owned foreground process groups. The Mac password goes directly to sudo's terminal.

The app and supervisor communicate through a private folder under `~/Library/Application Support/Betterer Connect/Sessions`. It contains a non-secret request, an owner heartbeat, a stop marker, and enumerated status. SSO configuration and Qt browser data are isolated there and removed after teardown. Raw output is bounded in memory and discarded. The app receives no authentication transcript, cookies, or tokens. Diagnostics omit gateway and group as well.

Cancellation interrupts only the owned process group. It does not declare disconnection until that group is gone. A missing heartbeat requests teardown; stale or uncertain status blocks another connection. Startup recovers and stops an unfinished previous session. There is no permanent root helper, sudoers modification, background daemon, login item, or updater.

The SSO helper passes the authentication cookie to OpenConnect through stdin. The app does not use `--authenticate`, custom disconnect hooks, certificate bypasses, custom route scripts, or arbitrary OpenConnect options. It does not inspect, stop, or uninstall other VPN clients. Avoid running competing VPN tunnels simultaneously.

## Limits and distribution

- Only sessions started by this app are tracked. Gateway compatibility, device posture requirements, and organization policy need local qualification.
- Status is based on OpenConnect output and supervisor health, not a probe of internal resources. Reconnect and sleep/wake need real-network testing.
- Terminal must remain open. Abrupt process termination, host shutdown, or a privileged child that will not exit can require manual recovery; the app keeps an unconfirmed state instead of claiming success.
- Browser data may exist during a session. Cleanup cannot guarantee secure erasure or recovery from a forced OS/process kill. See [security](SECURITY.md).
- The dependencies are installed separately under their own licenses. This app does not redistribute them.

To create a distribution package, supply your own Developer ID identities and configured notarytool profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
INSTALLER_IDENTITY='Developer ID Installer: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' \
scripts/package-release.sh
```

The release script signs, notarizes/staples the app, packages it, then notarizes/staples the installer. Dependencies still require separate installation. Builds target the current Mac architecture; Intel and hardened-runtime distribution behavior need separate qualification.

See [support](docs/support.md), [contributing](CONTRIBUTING.md), and [validation](docs/validation.md).
