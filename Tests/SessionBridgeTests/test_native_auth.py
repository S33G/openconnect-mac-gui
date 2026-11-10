import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).resolve().parents[2] / 'Resources/openconnect_auth.py'
spec = importlib.util.spec_from_file_location('auth', MODULE)
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)

class NativeAuthTests(unittest.TestCase):
    def response(self, cookie='synthetic-secret'):
        return (f"COOKIE='{cookie}'\nCONNECT_URL='https://vpn.example.com/group'\nFINGERPRINT='{'a' * 40}'\nRESOLVE='vpn.example.com:192.0.2.1'\n").encode()

    def test_native_browser_command_is_unprivileged_and_noninteractive(self):
        cmd = auth.auth_command('/opt/homebrew/bin/openconnect', 'vpn.example.com', 'Staff Users')
        self.assertIn('--external-browser=/usr/bin/open', cmd)
        self.assertIn('--non-inter', cmd)
        self.assertNotIn('/usr/bin/sudo', cmd)
        self.assertEqual(cmd[cmd.index('--authgroup') + 1], 'Staff Users')
        self.assertNotIn('--no-passwd', cmd)  # This also disables SSO in this flow.
        for host, group in [('-x', ''), ('vpn.example.com', 'x\ny')]:
            with self.assertRaises(ValueError): auth.auth_command('/tmp/oc', host, group)

    def test_cookie_is_data_never_shell_or_tunnel_argument(self):
        cookie = '$(touch /tmp/never-execute);`whoami`'
        fields = auth.parse_auth(self.response(cookie))
        self.assertEqual(fields.pop('COOKIE'), cookie)
        cmd = auth.tunnel_command('/tmp/openconnect', fields, True)
        self.assertNotIn(cookie, cmd)
        self.assertIn('--cookie-on-stdin', cmd)
        self.assertEqual(cmd[:3], ['/usr/bin/sudo', '-n', '/tmp/openconnect'])
        self.assertIn('--servercert', cmd)
        self.assertIn('--resolve', cmd)
        self.assertEqual(cmd[-1], 'https://vpn.example.com/group')

    def test_rejects_missing_duplicate_oversize_and_unsafe_fields(self):
        for data in [b'COOKIE=x', self.response() + b"COOKIE='second'\n", b'x' * 65537,
                     self.response().replace(b'https://vpn.', b'http://vpn.'),
                     self.response().replace(b'https://vpn.', b'https://user:pass@vpn.'),
                     self.response().replace(b'192.0.2.1', b'192.0.2.1;evil'),
                     self.response().replace(b'synthetic-secret', b'secret\x00')]:
            with self.assertRaises(ValueError): auth.parse_auth(data)

if __name__ == '__main__': unittest.main()
