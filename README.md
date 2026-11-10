# Betterer Connect

A native macOS menu-bar companion for Cisco Secure Client. Clear connection status, remembered gateways, browser sign-in handoff, and bounded reconnects after network changes.

Betterer Connect uses your existing Cisco installation. It includes no Cisco software and does not collect passwords, cookies, or tokens. This is an independent project, unaffiliated with Cisco or any employer. Cisco and AnyConnect are trademarks of their respective owners.

**Status:** early local prototype, version 0.1.0. Unit-tested connection logic; real VPN/SSO behavior still needs qualification across Cisco versions and organization policies. Development builds are ad-hoc signed, not notarized releases.

## Build and run

Requires macOS 13 or newer, Xcode with Swift 6 or newer, and an installed, working Cisco Secure Client (or legacy AnyConnect).

```sh
swift test --disable-sandbox
scripts/build-app.sh
open 'dist/Betterer Connect.app'
```

The app lives in the menu bar. Open its shield icon, choose a discovered gateway or add the DNS hostname supplied by IT, then click **Connect**. If authentication is needed, finish it in Cisco's window. Use **Copy gateway for Cisco** if Cisco needs the hostname entered manually. Betterer Connect never fills sign-in forms.

**Disconnect** stops automatic retries. **Reconnect automatically** only acts after you request a connection or the app observes an existing connected tunnel. Launching the app while disconnected does not start a VPN connection. Quit leaves Cisco and the tunnel running. The app has no login item or updater; launch it manually or deploy it using your organization's tools.

To preview the interface without running Cisco commands:

```sh
open 'dist/Betterer Connect.app' --args --demo
```

Quit any existing instance first. Preview mode does not simulate a successful connection.

## What it does

- Shows Connected, Connecting, Reconnecting, Needs sign-in, Offline, Missing Cisco, and Error states with explanations.
- Reads gateways from managed preferences and installed Cisco profiles; remembers your selection separately from a verified successful gateway.
- Opens Cisco for interactive authentication and observes for up to three minutes.
- Defers to an active Cisco connection attempt, with five bounded retry attempts and jitter when Cisco reports a dropped tunnel.
- Watches network path and sleep/wake, suppresses retry notifications while offline, and supports opt-in notifications.
- Copies diagnostics containing versions, state, selected gateway, and allowlisted error codes. Review internal gateway hostnames before sharing publicly.

## Configuration

Preference domain: `io.github.bettererconnect` (provisional; set `BUNDLE_ID` when packaging if you use your own domain). App defaults contain no gateways or company-specific support details. The public template at [`Packaging/managed-preferences.plist`](Packaging/managed-preferences.plist) is suitable as the custom-settings payload for an MDM tool. It is not itself a signed `.mobileconfig`.

| Key | Type | Default |
| --- | --- | --- |
| `GatewayList` | array of DNS hostnames | empty |
| `DefaultGateway` | DNS hostname | empty |
| `PreferredGroup` | string, UI hint only | empty |
| `AutoReconnect` | boolean | true |
| `MaxBackoffSeconds` | number, 2–3600 | 300 |
| `SupportChannel` | string shown after copying diagnostics | empty |

Managed preferences take precedence through macOS preferences. Gateway list order is preserved; the default gateway, last-used host, last selection, and profile hosts are appended without duplicates. The default selects the initial host. A user can select a different gateway for the current session. `LastSelectedGateway` remembers an explicit user selection. `LastUsedGateway` is written after a direct CLI connection or a hostname reported by Cisco stats; a connection appearing after GUI handoff does not prove the selected gateway was used. A managed `AutoReconnect` value locks the local toggle.

For an unmanaged development install, use your own gateway:

```sh
defaults write io.github.bettererconnect GatewayList -array vpn.example.com
defaults write io.github.bettererconnect DefaultGateway -string vpn.example.com
```

The example domain is intentionally non-operational. Do not commit organizational profiles, VPN transcripts, or diagnostics into this repository.

## Architecture

- `BetterConnectCore`: pure state machine, strict CLI parser, profile reader, validated configuration, and serialized process runner. Tests use synthetic hosts and harmless child processes.
- `BettererConnect`: SwiftUI menu/window, AppKit Cisco handoff, `NWPathMonitor`, sleep/wake watchers, notifications, and preferences.
- `scripts`: local app bundling and opt-in Developer ID/notarized package production. No downloaded dependencies or Cisco payload.

The CLI path is resolved in order: `/opt/cisco/secureclient/bin/vpn`, then `/opt/cisco/anyconnect/bin/vpn`. The service must also have a running `vpnagentd`. CLI output is transient and bounded; logs contain state and safe error codes only. CLI stdin is closed. Hostnames are passed as individual arguments without a shell.

## Limits

- CLI support and text formats vary. Unsupported or unknown state output stops automated actions and directs the user to Cisco. Parser fixtures are sanitized examples, not a compatibility certification.
- Frontmost Cisco UI and an app-initiated authentication handoff are treated as interactive ownership. The app does not inspect browser tabs or sheets. An independent sign-in in a background Cisco window cannot always be detected; command conflicts cause a fresh state check.
- Cisco owns SAML, MFA, certificates, posture, routing, and policy. Opening its UI cannot guarantee a particular gateway or completed sign-in. See [Cisco's authentication documentation](https://www.cisco.com/c/en/us/td/docs/security/asa/asa920/configuration/vpn/asa-920-vpn-config/vpn-anyconnect.html) for CLI/browser limitations.
- Network monitoring detects reachability and interface changes, not SSIDs. No Location or Accessibility access is requested.
- Cisco may already handle reconnect/resume. Check your VPN profile with IT before enabling overlapping automation. Betterer Connect waits while Cisco reports Connecting/Reconnecting.
- No privileged service restart, UI termination, credential automation, built-in telemetry, auto-update, or Cisco redistribution.

## Distribution

Local builds are for development. For distribution, supply your own Developer ID Application and Installer identities and a configured `notarytool` keychain profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
INSTALLER_IDENTITY='Developer ID Installer: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' \
scripts/package-release.sh
```

The release script signs with hardened runtime, notarizes/staples the app, packages only that app, then notarizes/staples the installer. It requires your signing credentials; none are included. Builds target the current Mac's architecture. Build/test on both Apple Silicon and Intel before advertising support for both; a universal release is not produced automatically.

See [validation](docs/validation.md), [support](docs/support.md), [contributing](CONTRIBUTING.md), and [security](SECURITY.md). MIT licensed.
