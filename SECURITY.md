# Security

Betterer Connect starts OpenConnect through the independently installed openconnect-sso helper. OpenConnect runs with administrator privileges to create the tunnel and configure routing/DNS. The app and its Python supervisor run as the logged-in user. No permanent privileged helper or sudoers policy is installed.

Mac administrator credentials are entered directly into sudo's controlling Terminal. Organization credentials and MFA are entered into the SSO helper's Qt browser. The app omits `--user`, disables autofill rules, isolates configuration, and sets a null keyring backend. It does not read or save VPN passwords. The SSO helper necessarily handles session cookies and supplies them to OpenConnect through stdin.

Raw subprocess output may contain authentication data. The supervisor processes bounded fragments in memory, emits only allowlisted lifecycle states, and discards the raw data. No raw transcript is displayed or stored. Diagnostics contain app/OS/dependency presence and safe status codes; no gateway, group, username, cookies, or tokens.

Preferences store gateway, authentication group, reconnect settings, and first-launch state. Private session files contain these non-secret launch settings, status, and control markers. Qt browser data and SSO configuration are isolated in the same mode-0700 folder, then removed after confirmed teardown. They can remain after a forced crash; cleanup is not secure erasure. The trust boundary includes locally installed Python, the SSO helper, OpenConnect, Qt, and Homebrew/pipx dependencies. Other code running as the same user can access that user's session files.

Hostnames and authentication groups are validated and passed as individual arguments. A generated Terminal command quotes fixed executable/resource paths. An atomic claim prevents duplicate or delayed launches. Only owned process groups are interrupted, and completed status requires that the group has exited. Uncertain teardown blocks new sessions. Normal Quit requests disconnection; an absent app heartbeat also requests it.

No certificate verification bypass, custom privileged route script, inherited disconnect shell hook, remote telemetry, or credential automation is provided.

For vulnerabilities, use the GitHub repository's private vulnerability reporting if enabled, otherwise contact the repository owner privately. Do not publish raw VPN transcripts or authentication material. No response SLA is promised for this development project.
