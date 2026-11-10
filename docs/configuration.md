# Configuration

Preference domain: `io.github.openconnectmacgui`. Public defaults are empty. The [managed preference template](../Packaging/managed-preferences.plist) is an MDM custom-settings example, not a signed mobileconfig.

| Key | Type | Default |
| --- | --- | --- |
| `GatewayList` | array of DNS hostnames | empty |
| `DefaultGateway` | DNS hostname | empty |
| `PreferredGroup` | authentication group | empty |
| `AutoReconnect` | boolean | true |
| `RunInBackground` | boolean | **false** |
| `MaxBackoffSeconds` | retry delay cap, 2–3600 | 300 |
| `SupportChannel` | optional support label | empty |

Managed values take precedence. Forced group, reconnect, and background settings lock their controls. Gateway selection and the last successfully used gateway are remembered separately. Connection settings apply to the next session.

The bundle identity changed for this rebrand. For an earlier unpublished development install, re-enter the gateway and group under the new identity. Public screenshots always use synthetic demo settings.

The GUI follows the Mac's appearance and accent preferences automatically. It provides no separate light/dark override. Connection success, warnings, and errors use semantic system colors.
