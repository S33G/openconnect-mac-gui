# Security

OpenConnect Mac GUI authenticates as the logged-in user through OpenConnect's native external-browser SSO. `/usr/bin/open` selects the user's default browser. The app does not inspect browser DOM, profiles, cookies, or history; passwords and MFA remain in the browser.

OpenConnect's authentication result necessarily contains a short-lived cookie. The adapter captures at most 64 KiB, parses quoted fields as data, validates connection metadata, and passes a bounded cookie through stdin. It never evaluates the output as a shell script. Cookies and administrator passwords are not saved to preferences, session files, logs, Terminal, clipboard, or command arguments. Python does not guarantee secure erasure of transient memory.

## Privileges and session ownership

Foreground sessions obtain normal sudo authorization in Terminal and run the tunnel with the privileges needed to configure routes and DNS. The foreground Terminal must stay open until disconnection.

Optional background sessions use the same per-session authorization, then start a bundled temporary privileged supervisor. It accepts validated connection metadata and a cookie through stdin, starts only the expected Homebrew OpenConnect executable with fixed options, and owns its process group. It does not accept arbitrary commands, route-script paths, environments, or additional arguments. Python runs with isolated imports, site initialization disabled, and bytecode writes disabled for this privileged bootstrap.

The bootstrap validates the sudo-established caller identity and private session directory before detaching. Two pipe acknowledgments transfer ownership before a tunnel can start. The Terminal supervisor stops publishing status after handoff and no longer treats Terminal closure as a stop request. The detached supervisor observes the native app's heartbeat and stop marker. App Quit requests disconnection; loss of heartbeat also requests teardown. The supervisor exits after the session ends. No persistent service, sudoers change, PAM change, or administrator-password storage is installed.

Status operations are anchored to the checked directory descriptor. Privileged writes use exclusive temporary files, no-follow opens, FD-based ownership changes, and atomic replacements. User-created status symlinks are not followed. Final completion requires the owned child group to exit; uncertain teardown blocks another connection.

The installed Homebrew OpenConnect/Python executables and bundled scripts are part of the administrator-approved trust boundary. Their user-writable installation paths are not a defense against malicious code already running as that user. This is one reason the project does not supply passwordless sudo rules for them.

## Files and diagnostics

Mode-0700 session folders store non-secret launch settings, a boot identifier, heartbeat, stop marker, ownership marker, and safe status. Raw subprocess output is bounded and discarded. Diagnostic copies contain dependency presence, app/OS version, settings, and safe codes, without hostnames, groups, usernames, cookies, or transcripts.

Completed folders are removed. Startup recovers prior sessions in place and uses a stable OS boot UUID to distinguish a reboot. The rebranded app blocks new connections while the earlier development app is running, avoiding competing reconnect loops. Other programs running as the same user can access that user's files and process memory; the session directory is not a sandbox boundary.

Normal OpenConnect certificate verification remains enabled. Browser retention follows the browser's own controls. OpenConnect and its installed vpnc-script manage routing and DNS. No third-party tunnel binaries are redistributed.

For vulnerabilities, use GitHub private vulnerability reporting if enabled, otherwise contact the repository owner privately. Do not publish real VPN transcripts or authentication material. No response SLA is promised for this development project.
