# Contributing

Use Xcode with Swift 6 and run `swift test --disable-sandbox` and `scripts/build-app.sh` before opening a pull request. Keep the core testable without Cisco installed. Include regression tests for retry, cancellation, and parsing changes.

Use `example.com` hostnames and synthetic identities in fixtures. Do not submit real CLI transcripts, internal gateways, cookies, tokens, passwords, company profiles, or personal diagnostics. Report the Cisco version and a minimal sanitized reproduction instead.

Do not implement credential automation, alternative tunnel clients, policy bypasses, privileged service management, or redistribution of Cisco binaries. Any change to signing, subprocess control, managed configuration, or diagnostics needs explicit review.

Test real connection flows only on a machine and VPN account you are authorized to use. Record unit tests separately from host integration, signing, notarization, and rollout evidence.
