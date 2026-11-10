> Historical plan, superseded by [OpenConnect migration](2026-11-10-openconnect.md). These backend constraints no longer describe version 0.2.0.

# Betterer Connect Implementation Plan

**Goal:** Build the supplied native macOS menu-bar app through M1/M2, with a runnable local app, tests, and distribution tooling.

**Architecture:** A pure, event-driven state machine owns connection intent, retries, and SSO ownership. A macOS adapter executes bounded Cisco processes and translates network/workspace events. SwiftUI renders that state. No external package dependencies.

**Tech stack:** Swift 6, Swift Package Manager, SwiftUI MenuBarExtra (macOS 13+), AppKit, Network, UserNotifications, XCTest.

## Constraints and decisions

- Follow the supplied build spec with the later user correction: generic open-source branding, repository name `betterer-connect`, no company-specific content.
- No Cisco redistribution, credential input, browser inspection, privilege escalation, or agent/UI termination.
- Bundle ID assumption: `io.github.bettererconnect`; confirm before managed distribution.
- Empty gateway defaults. User may enter a validated DNS hostname for bootstrap; managed gateways preserve their order. The selected host and verified last-used host are persisted separately; a GUI handoff may connect to a different host.
- Auto-reconnect defaults on, but requires connection intent established by user Connect or an observed active tunnel. User Disconnect cancels that intent until next Connect or relaunch observes a connection.
- Observe Cisco-native reconnect before issuing a new command. SSO ownership is latched until success, cancellation, or timeout; no Accessibility permission needed.
- Five retries, 2-second exponential base, 20% jitter, configurable cap (default 300 seconds). SSO timeout is 180 seconds.
- Open installed Cisco UI for auth. No undocumented URL scheme or browser automation; show selected gateway and copy button if Cisco requires manual selection.
- Treat CLI formats and environment-specific profile settings as integration evidence, not portable assumptions.
- Developer ID, notarization, IT ownership/approvals, and Jamf deployment are external rollout gates.

## Tasks

- [x] Core contract: add parser/config/reconnect/state-machine tests. Run failing tests, implement core, rerun.
  - Files: `Sources/BetterConnectCore/{Domain,Configuration,CiscoParser,ConnectionMachine}.swift`, `Tests/BetterConnectCoreTests/*`.
  - Validate exact state tokens, unknown/unsupported output, safe errors, gateway validation, managed precedence, retry cap/reset, SSO timeout, manual disconnect, stale results, network loss, missing client.
- [x] Runtime: implement bounded process runner and detector, then macOS event adapters.
  - Files: `Sources/BetterConnectCore/ProcessRunner.swift`, `Sources/BettererConnect/{CiscoService,AppModel}.swift`.
  - Validate real child process timeout/output bounds/closed stdin; command arguments must be arrays, no shell.
- [x] Native UI: status popover with gateway picker/bootstrap entry, connect/disconnect/retry, Cisco/Self Service actions, notifications, diagnostics.
  - Files: `Sources/BettererConnect/{BettererConnectApp,MenuContent}.swift`.
  - Build, launch bundled app, inspect UI through computer use if available.
- [x] Delivery: add app bundling/signing/notarization/package scripts, empty managed-preference template, support/validation docs.
  - Files: `Packaging/*`, `scripts/*`, `README.md`, `docs/{validation,support}.md`.
  - Run tests and release build, verify bundle metadata/signature/payload, launch local app, attempt authorized live VPN validation when feasible.

## Verification

`swift test --disable-sandbox` with module cache inside workspace; `scripts/build-app.sh`; `codesign --verify --deep --strict dist/'Betterer Connect.app'`; inspect app with macOS UI. Live failures are recorded separately from passing unit tests and local signing.
