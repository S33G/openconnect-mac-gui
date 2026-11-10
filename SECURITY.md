# Security

Betterer Connect uses OpenConnect's native external-browser SSO. Authentication runs as the logged-in user and opens the user's default browser through `/usr/bin/open`. Browser credentials and MFA remain in that browser. The app does not inspect the browser's DOM, cookies, profile, or history.

OpenConnect's `--authenticate` result necessarily includes a session cookie. A standard-library adapter captures this output through a bounded in-memory pipe, parses its quoted fields as data, and passes the cookie to the privileged tunnel over stdin. No shell evaluation is performed. No cookie is stored in preferences, session files, logs, Terminal, clipboard, or command arguments. Certificate and validated connection metadata are passed as separate arguments. `--non-inter` prevents console credential prompts; certificate checks remain enabled.

The app and supervisor run without root privileges. Administrator access is obtained through a normal sudo prompt in Terminal; the subsequent tunnel command uses sudo's noninteractive mode. No permanent privileged helper or sudoers policy is installed. OpenConnect and its installed vpnc-script run with the privilege required to configure the tunnel, routes, and DNS.

The supervisor bounds and discards raw output, emitting allowlisted lifecycle states only. Diagnostic copies contain dependency presence, OS/app version, and safe codes; no hostname, authentication group, username, cookie, or raw transcript. Temporary in-memory authentication material is not guaranteed to be securely erased by Python.

Mode-0700 session folders store non-secret host/group settings, boot identity, heartbeat, stop marker, and status. Atomic claims prevent duplicate/delayed launches. Completed status requires the owned process group to exit. An absent app heartbeat requests teardown; uncertain cleanup blocks another connection. Completed folders are removed, and previous-boot sessions can be retired safely. Other programs running as the same user can access that user's files/process memory; this is not a sandbox boundary.

The trust boundary includes OpenConnect, Python, Homebrew dependencies, the operating system, and the user's browser. Browser cookies/history use its normal retention settings. No third-party tunnel binaries are bundled.

Use GitHub private vulnerability reporting if enabled, otherwise contact the repository owner privately. Do not publish real VPN transcripts or authentication material. No security response SLA is promised for this development project.
