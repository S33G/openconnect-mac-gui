# Security

Betterer Connect is a user-space controller for an existing Cisco client. It does not implement a tunnel or authenticate users. Cisco and the organization's VPN policies remain responsible for authentication and network access.

No passwords, browser state, cookies, or SSO tokens are read or stored. Connection preferences written by the app are the validated selected and verified last-used gateway hostnames. A reconnect preference and first-launch flag are also stored. Diagnostics include gateway hostnames, which may be private organizational information. Logging uses enumerated states and error codes, never raw CLI output.

Process execution uses a fixed executable path, argument arrays, closed stdin, output limits, and deadlines. Cancelling a command terminates only the CLI child created by this app. Cisco UI and vpnagentd are never terminated or restarted.

For a security issue, use the repository's private vulnerability reporting feature if the maintainer has enabled it. If that feature is unavailable, contact the repository owner privately before publishing sensitive details. No security response SLA is promised for this early prototype.
