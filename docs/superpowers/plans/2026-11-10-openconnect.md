> The native external-browser flow in version 0.3.0 supersedes the Qt/openconnect-sso parts of this migration. OpenConnect authenticates as the user, with an in-memory cookie pipe to the privileged tunnel.

# OpenConnect backend migration

User direction supersedes the original invoke-only Cisco design. Keep the native UI layout and open-source branding; remove Cisco client dependency completely.

- [x] Replace Cisco polling/GUI ownership with owned OpenConnect session lifecycle and tests. Connect must mean a configured tunnel, not a live SSO process. Disconnect remains pending until owned processes stop.
- [x] Add a bundled, unprivileged Python session supervisor. Launch in Terminal for sudo's own administrator prompt. Run openconnect-sso without --user, using an isolated XDG config with autofill disabled and null keyring backend. Browser SSO is visible; credentials remain with the external SSO helper.
- [x] Read only bounded, allowlisted lifecycle status from the supervisor. Keep raw output/cookies/passwords out of the app, persistent logs, preferences, diagnostics and status files. Stop only the owned process group; never global pkill.
- [x] Preserve gateway/status cards and controls; replace Cisco actions with dependency setup and session Terminal. Add an editable auth group. Defaults remain empty and generic.
- [x] Supply compatible dependency setup, documentation and tests. Rebuild/archive the app and exercise the administrator handoff. Full browser SSO/tunnel validation remains a human-authentication gate.

Architecture: Swift core lifecycle policy; Swift macOS adapter creates a private session descriptor and launches a .command file; Python supervisor starts the installed SSO CLI in its own foreground process group, parses bounded output into safe status, monitors a stop marker and app heartbeat, and forwards interrupt for teardown. OpenConnect's own vpnc-script owns routes/DNS; the app does not customize them.

Privileges: no permanent helper or sudoers changes. openconnect-sso invokes sudo; administrator password is entered directly into the controlling Terminal. Full live tunnel qualification needs human MFA and administrator approval.
