# OpenConnect Mac GUI

Native macOS menu-bar app for OpenConnect with default-browser SSO and optional background sessions. Follows the macOS appearance and accent color.

## Requirements

- macOS 13+ and Xcode with Swift 6+.
- Homebrew OpenConnect and Python 3.11+.
- A VPN gateway supporting OpenConnect's external-browser SSO.

## Build and run

```sh
brew install openconnect python@3.11
scripts/build-app.sh
open 'dist/OpenConnect Mac GUI.app'
```

Enter your VPN hostname and authentication group, click **Connect**, then complete the Terminal administrator prompt and browser SSO. Use **Disconnect** to stop the VPN.

- **Foreground (default):** keep Terminal open while connected.
- **Run VPN in background:** close Terminal after **BACKGROUND READY**. Keep the app running.
- Quitting the app disconnects in either mode. Startup requires administrator authorization; see [authorization options](docs/administrator-access.md).

## Screenshots

| Light | Dark |
| :---: | :---: |
| <img src="docs/images/ui-light.png" alt="Light appearance using vpn.example.com" width="370"> | <img src="docs/images/ui-dark.png" alt="Dark appearance using vpn.example.com" width="370"> |

## Tests

```sh
swift test --disable-sandbox
python3 -m unittest discover -s Tests/SessionBridgeTests -v
```

Development build **0.4.0**, ad-hoc signed and not notarized. See [validation](docs/validation.md), [support](docs/support.md), [security](SECURITY.md), and [contributing](CONTRIBUTING.md).

<img src="docs/images/connection-hero.png" alt="Silver and graphite connection links" width="720">

[MIT license](LICENSE). OpenConnect is installed separately under its own license. Independent project, unaffiliated with OpenConnect maintainers or VPN vendors.
