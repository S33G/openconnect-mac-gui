import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

BRIDGE = Path(__file__).resolve().parents[2] / 'Resources' / 'session_bridge.py'

class BridgeTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location('bridge', BRIDGE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_parser_never_confuses_authentication_with_a_tunnel(self):
        m = self.module()
        self.assertEqual(m.classify('Authentication successful cookie=secret'), 'authorizing')
        self.assertIsNone(m.classify('Got CONNECT response: HTTP/1.1 200 OK'))
        self.assertEqual(m.classify('Configured as 10.0.0.2, with SSL connected and DTLS connected'), 'connected')
        self.assertEqual(m.classify('SSL negotiation with vpn.example.com'), 'connecting')
        self.assertEqual(m.classify('Server certificate verify failed'), 'certificate_failed')
        self.assertIsNone(m.classify('password=secret token=another username=private@example.com'))
        self.assertIsNone(m.classify('A message quoted: Configured as 10.0.0.2, with SSL connected'))

    def test_commands_disable_password_capture_and_pass_group_as_one_argument(self):
        m = self.module()
        cmd = m.command('/tmp/openconnect-sso', 'vpn.example.com', 'Staff Users', True)
        self.assertNotIn('--user', cmd)
        self.assertNotIn('--authenticate', cmd)
        self.assertEqual(cmd[cmd.index('--authgroup') + 1], 'Staff Users')
        self.assertIn('--browser-display-mode', cmd)
        with self.assertRaises(ValueError): m.command('/tmp/openconnect-sso', '-x', '', True)
        with self.assertRaises(ValueError): m.command('/tmp/openconnect-sso', 'vpn.example.com', 'x\ny', True)

    def test_private_environment_cannot_load_saved_credentials(self):
        m = self.module()
        with tempfile.TemporaryDirectory() as folder:
            env = m.environment(Path(folder), '/opt/homebrew/bin/openconnect')
            self.assertEqual(env['PYTHON_KEYRING_BACKEND'], 'keyring.backends.null.Keyring')
            self.assertEqual(env['XDG_CONFIG_HOME'], env['XDG_CONFIG_DIRS'])
            config = Path(env['XDG_CONFIG_HOME']) / 'openconnect-sso/config.toml'
            self.assertEqual(config.read_text(), 'auto_fill_rules = {}\n')
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)

    def test_supervisor_streams_safe_status_and_stops_only_owned_session(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            fixture = root / 'fixture.py'
            fixture.write_text("import time\nprint('Configured as 10.0.0.2, with SSL connected', flush=True)\nprint('password=SECRET token=SECRET', flush=True)\ntime.sleep(60)\n")
            (root / 'owner').touch()
            code = f"import importlib.util;from pathlib import Path;s=importlib.util.spec_from_file_location('b',{str(BRIDGE)!r});m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.supervise([{sys.executable!r},{str(fixture)!r}],Path({folder!r}),dict(__import__('os').environ),'fixture',None)"
            proc = subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            unrelated = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(60)'])
            try:
                deadline = time.time() + 5
                status = {}
                while time.time() < deadline:
                    if (root / 'status.json').exists():
                        status = json.loads((root / 'status.json').read_text())
                        if status['phase'] == 'connected': break
                    time.sleep(0.03)
                self.assertEqual(status.get('phase'), 'connected')
                self.assertNotIn('SECRET', (root / 'status.json').read_text())
                (root / 'stop').touch()
                proc.wait(timeout=5)
                status = json.loads((root / 'status.json').read_text())
                self.assertEqual(status['phase'], 'stopped')
                self.assertIsNone(unrelated.poll())
            finally:
                if proc.poll() is None: proc.kill()
                unrelated.terminate(); unrelated.wait()
                if proc.stderr: proc.stderr.close()

class LifecycleTests(unittest.TestCase):
    def run_fixture(self, root, setup, call):
        code = f"import importlib.util,os,sys;from pathlib import Path;s=importlib.util.spec_from_file_location('b',{str(BRIDGE)!r});m=importlib.util.module_from_spec(s);s.loader.exec_module(m);root=Path({str(root)!r});" + '\n' + setup + '\n' + call
        return subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_owner_loss_interrupts_session_and_confirms_teardown(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'owner').touch()
            os.utime(root / 'owner', (0, 0))
            p = self.run_fixture(root, '', "m.supervise([sys.executable,'-c','import time;time.sleep(60)'],root,dict(os.environ),'fixture',None)")
            p.wait(timeout=5)
            state = json.loads((root / 'status.json').read_text())
            self.assertTrue(state['finished'])
            self.assertEqual(state['phase'], 'stopped')

    def test_terminal_failure_after_spawn_still_reaps_child(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'owner').touch()
            # Invalid tty fails after Popen, exercising the error teardown path.
            p = self.run_fixture(root, '', "m.supervise([sys.executable,'-c','import time;time.sleep(60)'],root,dict(os.environ),'fixture',-1)")
            p.wait(timeout=5)
            state = json.loads((root / 'status.json').read_text())
            self.assertTrue(state['finished'])
            self.assertEqual(state['phase'], 'session_failed')

    def test_cancelled_claim_prevents_delayed_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'claimed').mkdir()
            # No request file: a cancelled claim must exit before reading/spawning.
            p = subprocess.run([sys.executable, str(BRIDGE), str(root)], timeout=5, capture_output=True)
            self.assertEqual(p.returncode, 0)
            self.assertFalse((root / 'status.json').exists())

    def test_missing_terminal_finishes_without_spawning(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'request.json').write_text(json.dumps(dict(sessionID='fixture')))
            setup = """
real_open=m.os.open
def fail_tty(path,*a,**kw):
    if path=='/dev/tty': raise OSError('terminal closed')
    return real_open(path,*a,**kw)
m.os.open=fail_tty
sys.argv=['bridge',str(root)]
"""
            p = self.run_fixture(root, setup, 'm.main()')
            p.wait(timeout=5)
            state = json.loads((root / 'status.json').read_text())
            self.assertTrue(state['finished'])
            self.assertEqual(state['phase'], 'session_failed')

    def test_cancel_during_admin_stage_emits_completed_status(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'owner').touch()
            (root / 'request.json').write_text(json.dumps(dict(sessionID='fixture', sso='/not/launched', openconnect='/tmp/openconnect', host='vpn.example.com', group='', autoReconnect=True)))
            # Keep main's real sequencing; replace only sudo with a harmless child,
            # and the controlling tty with None (this fixture reads no password).
            setup = """
real_popen=m.subprocess.Popen
real_open=m.os.open
real_close=m.os.close
m.subprocess.Popen=lambda args,**kw: real_popen([sys.executable,'-c','import time;time.sleep(60)'] if args[0]=='/usr/bin/sudo' else args,**kw)
m.os.open=lambda path,*a,**kw: None if path=='/dev/tty' else real_open(path,*a,**kw)
m.os.close=lambda fd: None if fd is None else real_close(fd)
sys.argv=['bridge',str(root)]
"""
            p = self.run_fixture(root, setup, 'm.main()')
            try:
                deadline = time.time() + 5
                while time.time() < deadline and not (root / 'status.json').exists(): time.sleep(0.02)
                self.assertTrue((root / 'status.json').exists())
                (root / 'stop').touch()
                p.wait(timeout=5)
                state = json.loads((root / 'status.json').read_text())
                self.assertTrue(state['finished'])
                self.assertEqual(state['phase'], 'stopped')
            finally:
                if p.poll() is None: p.kill(); p.wait()

if __name__ == '__main__': unittest.main()
