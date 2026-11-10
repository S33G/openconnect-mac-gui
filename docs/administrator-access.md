# Administrator authorization

OpenConnect needs administrator privileges to create the tunnel and configure routes/DNS. Browser SSO does not require those privileges. Background mode separates these phases and keeps a temporary supervisor for the active session, so disconnecting later does not need another password.

## Options

| Approach | Experience | Assessment |
| --- | --- | --- |
| Per-session sudo, as shipped | Authorize startup; close Terminal after background handoff | Smallest implementation. No installed service or authorization-policy change. Existing valid sudo timestamps are honored. |
| Touch ID for sudo | Use a fingerprint in place of typing when macOS allows it | Practical local improvement. Still requires startup approval and suitable hardware/session policy. |
| Native privileged helper | Approve a system service during setup; connect/disconnect through the app | Best long-term product experience. Needs authenticated IPC, a narrowly scoped command surface, stable signing, registration/removal UX, and full qualification. |
| Longer sudo caching | Fewer prompts within the configured scope and lifetime | Not a substitute for a helper. Cache policy and terminal association vary; the app should not keep credentials alive indefinitely. |
| Passwordless sudo rules | Removes a prompt for commands allowed by the rule | Not recommended for this app's Homebrew executables or scripts. OpenConnect supports privileged script options, and user-writable paths make broad rules particularly unsafe. |

## Touch ID

Recent macOS installations provide `/etc/pam.d/sudo_local.template`, with Apple's commented `pam_tid.so` configuration. A local administrator can review that template and the Mac's management policy before enabling the corresponding entry in `sudo_local`. Use the local template for the installed OS; do not overwrite an existing PAM file blindly.

This project does not change PAM or sudoers. Touch ID availability can depend on the Mac, input hardware, remote-session state, and organization policy. A password fallback may still be required.

## Native privileged helper

Apple's [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) supports app-owned launch daemons. Registration of a daemon is [subject to administrator approval](https://developer.apple.com/documentation/servicemanagement/smappservice/register()). A production implementation should verify the calling app, accept only validated connection data, and own the tunnel and its teardown through a small authenticated API.

It should not expose an arbitrary command runner, accept caller-selected script paths, or blindly trust user-writable executable paths. Package identity, helper updates, app removal, and crash recovery also need review. Stable app/helper signing is a prerequisite for a reliable distribution experience; an ad-hoc development bundle is not a substitute for qualifying that lifecycle.

A helper can remove routine Terminal password prompts after setup approval. It does not remove VPN SSO/MFA required by the server.

## Current implementation

Background mode uses a per-session privileged bootstrap, authorized through sudo. It receives authentication material only through stdin, opens the checked private session directory, and hands the active session to a detached supervisor. The app heartbeat and stop marker remain authoritative. The supervisor exits after its session ends; no launch daemon is registered or installed.

The implementation uses sudo's normal authorization lifetime without changing it, periodically renewing it, or saving the administrator password. See the upstream [sudoers manual](https://www.sudo.ws/docs/man/sudoers.man/) for timestamp policy and command-matching details.
