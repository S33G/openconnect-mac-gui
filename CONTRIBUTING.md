# Contributing

Use Swift 6 and Python 3.11+. Run `swift test --disable-sandbox`, `python3 -m unittest discover -s Tests/SessionBridgeTests -v`, and `scripts/build-app.sh` before submitting a change. Core and supervisor fixture tests need no VPN account, root privilege, or installed VPN client.

Use example.com hosts and synthetic identities. Never submit real VPN transcripts, internal hostnames, cookies, tokens, passwords, profiles, or personal diagnostics. Include dependency versions and a sanitized reproduction.

Changes to privilege handling, process ownership, browser-data isolation, cancellation, configuration, and diagnostics need careful review and regression tests. Keep runtime dependencies separate; do not bundle their binaries or implement certificate verification bypasses. Check upstream parser behavior when updating the pinned SSO version.

Test live flows only on a machine and VPN account you are authorized to use. Distinguish unit tests, harmless subprocess tests, real tunnel behavior, signing, and distribution evidence.
