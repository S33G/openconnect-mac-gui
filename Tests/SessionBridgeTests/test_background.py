import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

RESOURCES = Path(__file__).resolve().parents[2] / 'Resources'

def module(name):
    spec = importlib.util.spec_from_file_location(name, RESOURCES / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

class BackgroundTests(unittest.TestCase):
    def test_safe_status_replaces_symlink_without_touching_its_target(self):
        bridge = module('session_bridge')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / 'untouched'
            target.write_text('do not overwrite')
            (root / 'status.json').symlink_to(target)
            with bridge.Runtime(root, owner=(os.getuid(), os.getgid())) as runtime:
                bridge.status(runtime, 'fixture', 'connected')
            self.assertEqual(target.read_text(), 'do not overwrite')
            self.assertFalse((root / 'status.json').is_symlink())
            self.assertEqual((root / 'status.json').stat().st_mode & 0o777, 0o600)

    def test_runtime_remains_anchored_when_directory_is_renamed(self):
        bridge = module('session_bridge')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'session'; root.mkdir(mode=0o700)
            with bridge.Runtime(root) as runtime:
                root.rename(Path(folder) / 'original')
                root.mkdir(mode=0o700)
                bridge.status(runtime, 'fixture', 'connected')
            self.assertFalse((root / 'status.json').exists())
            self.assertTrue((Path(folder) / 'original/status.json').exists())

    def test_detached_supervisor_survives_launcher_and_stops_on_app_request(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'owner').touch()
            fixture = "import time;print('Configured as 192.0.2.1, with SSL connected',flush=True);time.sleep(60)"
            code = f"import sys;sys.path.insert(0,{str(RESOURCES)!r});import headless_tunnel as b;from pathlib import Path;b.detach(Path({folder!r}),'fixture',[{sys.executable!r},'-c',{fixture!r}],dict(__import__('os').environ),b'',(__import__('os').getuid(),__import__('os').getgid()))"
            launcher = subprocess.run([sys.executable, '-c', code], capture_output=True, timeout=5)
            self.assertEqual(launcher.returncode, 0, launcher.stderr.decode())
            deadline = time.time() + 5
            state = {}
            while time.time() < deadline:
                if (root / 'status.json').exists():
                    state = json.loads((root / 'status.json').read_text())
                    if state['phase'] == 'connected': break
                time.sleep(0.03)
            try:
                self.assertEqual(state.get('phase'), 'connected')
                handoff = json.loads((root / 'detached.json').read_text())
                self.assertEqual(handoff['sessionID'], 'fixture')
                self.assertTrue(handoff['detached'])
            finally:
                (root / 'stop').touch()
            deadline = time.time() + 5
            while time.time() < deadline:
                state = json.loads((root / 'status.json').read_text())
                if state['finished']: break
                time.sleep(0.03)
            self.assertTrue(state['finished'])
            self.assertEqual(state['phase'], 'stopped')

    def test_terminal_supervisor_relinquishes_ownership_and_app_loss_stops_daemon(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root / 'owner').touch()
            fixture = "import time;print('Configured as 192.0.2.1, with SSL connected',flush=True);time.sleep(60)"
            child = f"import sys,os;sys.path.insert(0,{str(RESOURCES)!r});import headless_tunnel as b;from pathlib import Path;b.detach(Path({folder!r}),'fixture',[sys.executable,'-c',{fixture!r}],dict(os.environ),b'',(os.getuid(),os.getgid()))"
            parent = f"import sys,os;sys.path.insert(0,{str(RESOURCES)!r});import session_bridge as s;from pathlib import Path;result=s.supervise([sys.executable,'-c',{child!r}],Path({folder!r}),dict(os.environ),'fixture',None,allow_handoff=True);assert result==s.HANDOFF_EXIT"
            p = subprocess.run([sys.executable, '-c', parent], capture_output=True, timeout=5)
            self.assertEqual(p.returncode, 0, p.stderr.decode())
            deadline=time.time()+5; state={}
            while time.time()<deadline:
                state=json.loads((root/'status.json').read_text())
                if state['phase']=='connected': break
                time.sleep(0.02)
            try:
                self.assertEqual(state.get('phase'),'connected')
                self.assertFalse(state['finished'])
            finally:
                os.utime(root/'owner',(0,0))
            deadline=time.time()+5
            while time.time()<deadline:
                state=json.loads((root/'status.json').read_text())
                if state['finished']: break
                time.sleep(0.03)
            self.assertTrue(state['finished'])
            self.assertEqual(state['phase'],'stopped')

    def test_cancel_before_handoff_never_starts_tunnel(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); (root/'owner').touch(); (root/'stop').touch()
            fixture=f"from pathlib import Path;Path({str(root/'spawned')!r}).touch()"
            code=f"import sys,os;sys.path.insert(0,{str(RESOURCES)!r});import headless_tunnel as b;from pathlib import Path;b.detach(Path({folder!r}),'fixture',[sys.executable,'-c',{fixture!r}],dict(os.environ),b'',(os.getuid(),os.getgid()))"
            p=subprocess.run([sys.executable,'-c',code],capture_output=True,timeout=5)
            self.assertEqual(p.returncode,0,p.stderr.decode())
            deadline=time.time()+5; state={}
            while time.time()<deadline:
                if (root/'status.json').exists():
                    state=json.loads((root/'status.json').read_text())
                    if state['finished']: break
                time.sleep(0.03)
            self.assertTrue(state['finished'])
            self.assertFalse((root/'spawned').exists())

    def test_invalid_handoff_marker_cannot_block_reader(self):
        bridge=module('session_bridge')
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); os.mkfifo(root/'detached.json')
            with bridge.Runtime(root) as runtime:
                self.assertFalse(runtime.handed_off('fixture'))

    def test_background_payload_requires_bounded_secret_and_fixed_executable(self):
        native = module('openconnect_auth')
        fields = native.parse_auth(("COOKIE='synthetic'\nCONNECT_URL='https://vpn.example.com'\nFINGERPRINT='" + 'a'*40 + "'\n").encode())
        self.assertEqual(native.validate_fields(fields), fields)
        with self.assertRaises(ValueError): native.validate_fields(dict(fields, COOKIE='a'*4096))
        background = module('headless_tunnel')
        with self.assertRaises(ValueError): background.validate_executable('/bin/sh')

if __name__ == '__main__': unittest.main()
