#!/usr/bin/env python3
"""Private session supervisor. Never persists or forwards authentication output."""
import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
import stat
import uuid


HANDOFF_EXIT = 75

def classify(line):
    # Parse lifecycle messages only. Everything else is discarded.
    text = line.lower()
    if 'server certificate verify failed' in text or 'certificate verification failed' in text:
        return 'certificate_failed'
    if 'no sso handler' in text:
        return 'browser_unsupported'
    if 'sudo:' in text and ('password' in text or 'not allowed' in text):
        return 'permission_failed'
    if 'opening default browser for sso' in text:
        return 'needs_sso'
    if 'authentication failed' in text or 'authentication cancelled' in text:
        return 'authentication_failed'
    if re.match(r'^configured as .+, with ssl connected(?: |$)', text.strip()):
        return 'connected'
    if 'reconnecting' in text or 'reconnect in ' in text or 'ssl connection failure' in text:
        return 'reconnecting'
    if 'ssl negotiation with ' in text:
        return 'connecting'
    if 'authentication successful' in text:
        return 'authorizing'
    return None


def environment(root, openconnect):
    env = {k: v for k, v in os.environ.items() if k in ('HOME', 'USER', 'LOGNAME', 'TMPDIR')}
    env.update(PATH=str(Path(openconnect).parent) + ':/usr/bin:/bin:/usr/sbin:/sbin',
               LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8')
    return env


class Runtime:
    """Anchor file operations; privileged writers never follow client symlinks."""
    def __init__(self, path, owner=None):
        self.path = Path(path)
        self.fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        self.owner = owner
        if owner is not None:
            info = os.fstat(self.fd)
            if info.st_uid != owner[0] or stat.S_IMODE(info.st_mode) != 0o700:
                os.close(self.fd)
                raise ValueError('unsafe session directory')
    def __enter__(self): return self
    def __exit__(self, *args): os.close(self.fd)
    def exists(self, name):
        try: os.stat(name, dir_fd=self.fd, follow_symlinks=False); return True
        except FileNotFoundError: return False
    def owner_lost(self):
        try:
            info = os.stat('owner', dir_fd=self.fd, follow_symlinks=False)
            return not stat.S_ISREG(info.st_mode) or (self.owner is not None and info.st_uid != self.owner[0]) or time.time() - info.st_mtime > 20
        except FileNotFoundError: return True
    def write_json(self, name, value):
        temporary = '.write-' + uuid.uuid4().hex
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=self.fd)
        try:
            if self.owner is not None: os.fchown(fd, *self.owner)
            with os.fdopen(fd, 'w') as stream:
                fd = None
                json.dump(value, stream)
            os.replace(temporary, name, src_dir_fd=self.fd, dst_dir_fd=self.fd)
        finally:
            if fd is not None: os.close(fd)
            try: os.unlink(temporary, dir_fd=self.fd)
            except FileNotFoundError: pass
    def request_stop(self): self.write_json('stop', {})
    def handed_off(self, session):
        try:
            fd = os.open('detached.json', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=self.fd)
            with os.fdopen(fd, 'r') as stream:
                if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode): return False
                value = json.loads(stream.read(4097))
            return value.get('sessionID') == session and value.get('detached') is True
        except (OSError, ValueError): return False


def status(root, session, phase, finished=False):
    value = dict(sessionID=session, phase=phase, updatedAt=time.time(), finished=finished)
    if isinstance(root, Runtime): root.write_json('status.json', value)
    else:
        with Runtime(root) as runtime: runtime.write_json('status.json', value)


def group_alive(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def supervise(args, root, env, session, tty, phase='needs_sso', interactive=False, stdin_data=None, allow_handoff=False):
    """Return the exit code only after the owned process group has gone away."""
    owned_runtime = not isinstance(root, Runtime)
    runtime = Runtime(root) if owned_runtime else root
    def handed_off(): return allow_handoff and runtime.handed_off(session)
    def publish(phase, finished=False):
        if not handed_off(): status(runtime, session, phase, finished)
    proc = subprocess.Popen(args, env=env, stdin=subprocess.PIPE if stdin_data is not None else (None if interactive else subprocess.DEVNULL),
                            stdout=None if interactive else subprocess.PIPE,
                            stderr=None if interactive else subprocess.STDOUT, process_group=0)
    previous = None
    selector = None
    pending = b''
    stopped = None
    failure = None
    started = time.monotonic()
    heartbeat = 0
    had_tunnel = False
    authenticated = False
    try:
        if stdin_data is not None:
            proc.stdin.write(stdin_data)
            proc.stdin.close()
        selector = selectors.DefaultSelector()
        if tty is not None:
            previous = os.tcgetpgrp(tty)
            os.tcsetpgrp(tty, proc.pid)
        if proc.stdout:
            os.set_blocking(proc.stdout.fileno(), False)
            selector.register(proc.stdout, selectors.EVENT_READ)
        while True:
            now = time.monotonic()
            owner_lost = runtime.owner_lost()
            expired = not had_tunnel and now - started > 180
            if stopped is None and (runtime.exists('stop') or owner_lost or expired):
                stopped = now
                if expired:
                    failure = 'sign_in_timeout'
                phase = 'disconnecting'
                try: os.killpg(proc.pid, signal.SIGINT)
                except (ProcessLookupError, PermissionError): pass
            if stopped is not None and now - stopped > 12:
                phase = 'disconnect_stuck'
            if now - heartbeat > 0.5:
                publish(phase)
                heartbeat = now
            for key, _ in selector.select(0.1):
                chunk = os.read(key.fd, 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                pending += chunk
                lines = pending.split(b'\n')
                pending = lines.pop()[-16384:]
                for line in lines:
                    observed = classify(line[-16384:].decode('utf-8', 'replace'))
                    if observed and stopped is None:
                        if observed == 'authorizing': authenticated = True
                        # --servercert may accept the authenticated pin after a CA warning.
                        # A configured tunnel proves OpenConnect completed its TLS checks.
                        if observed == 'connected' and failure == 'certificate_failed': failure = None
                        if observed == 'connecting' and not (authenticated or had_tunnel): continue
                        if observed.endswith('_failed') or observed == 'browser_unsupported':
                            if failure is None or failure == 'authentication_failed': failure = observed
                        phase = failure or observed
                        had_tunnel = had_tunnel or observed == 'connected'
            if interactive:
                time.sleep(0.1)
            code = proc.poll()
            if code is not None and not group_alive(proc.pid):
                final = failure or ('stopped' if stopped is not None else ('exited' if code == 0 else 'session_failed'))
                if handed_off(): return HANDOFF_EXIT
                publish(final, finished=not interactive)
                return code if stopped is None else -1
            # If the SSO parent exits while its tunnel remains, keep owning and supervising it.
            if code is not None and stopped is None:
                stopped = now
                phase = 'disconnecting'
                try: os.killpg(proc.pid, signal.SIGINT)
                except (ProcessLookupError, PermissionError): pass
    except Exception:
        # A parser, pipe or terminal error must never release a live tunnel.
        try: os.killpg(proc.pid, signal.SIGINT)
        except (ProcessLookupError, PermissionError): pass
        while proc.poll() is None or group_alive(proc.pid):
            try: publish('disconnect_stuck')
            except OSError: pass
            time.sleep(0.5)
        publish('session_failed', finished=not interactive)
        return -1
    finally:
        if selector is not None: selector.close()
        if proc.stdout: proc.stdout.close()
        if owned_runtime: runtime.__exit__()
        if tty is not None and previous is not None:
            try: os.tcsetpgrp(tty, previous)
            except OSError: pass


def main():
    os.umask(0o077)
    root = Path(sys.argv[1]).resolve()
    try:
        (root / 'claimed').mkdir(mode=0o700)
    except FileExistsError:
        return  # One launcher owns this request; cancellation may have claimed it.
    spec = json.loads((root / 'request.json').read_text())
    session = spec['sessionID']
    if (root / 'stop').exists():
        status(root, session, 'stopped', True)
        return
    tty = None
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    # Terminal closure asks the owned group to exit; keep supervising teardown.
    def stop(_signal, _frame):
        try:
            with Runtime(root) as runtime:
                if not runtime.handed_off(session): runtime.request_stop()
        except FileNotFoundError: pass  # The app already cleaned a completed session.
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(sig, stop)
    try:
        tty = os.open('/dev/tty', os.O_RDWR)
        args = [sys.executable, str(Path(__file__).with_name('openconnect_auth.py')), str(root / 'request.json')]
        env = environment(root, spec['openconnect'])
        print(r"""
+--------------------------------------------------------------+
|  o==o  OpenConnect Mac GUI                                   |
|        Browser SSO. App-owned VPN sessions.                  |
+--------------------------------------------------------------+
""", flush=True)
        if spec.get('runInBackground', False):
            print("""[MODE] BACKGROUND (HEADLESS)
Keep Terminal open during startup.
Wait for: "BACKGROUND READY - safe to close this window".
The menu-bar app owns the VPN; quitting it disconnects.
""", flush=True)
        else:
            print("""[MODE] FOREGROUND
IMPORTANT: KEEP THIS TERMINAL WINDOW OPEN WHILE CONNECTED.
Closing it requests VPN disconnection.
Use the app to disconnect, then close this window.
""", flush=True)
        print("""Enter your Mac password at the sudo prompt.
Sign-in in your default browser follows.
""", flush=True)
        status(root, session, 'permission')
        if supervise(['/usr/bin/sudo', '-v'], root, env, session, tty, 'permission', True) != 0:
            prior = json.loads((root / 'status.json').read_text())['phase']
            final = prior if prior in ('stopped', 'sign_in_timeout') else 'permission_failed'
            status(root, session, final, True)
            return
        if (root / 'stop').exists():
            status(root, session, 'stopped', True)
            return
        print('Complete sign-in in your default browser. Use OpenConnect Mac GUI to disconnect.', flush=True)
        result = supervise(args, root, env, session, tty, allow_handoff=spec.get('runInBackground', False))
        if result == HANDOFF_EXIT:
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(sig, signal.SIG_IGN)
            print('BACKGROUND READY - safe to close this window.\nKeep OpenConnect Mac GUI running to maintain the VPN.\nUse Disconnect in the app to stop it.', flush=True)
            return
        print('VPN session ended. You can close this Terminal window.', flush=True)
    except Exception:
        # Never print exception details: library exceptions can contain credentials.
        with Runtime(root) as runtime:
            if runtime.handed_off(session): return
        status(root, session, 'session_failed', True)
        print('Session could not start. Return to OpenConnect Mac GUI for the safe status code.', flush=True)
    finally:
        if tty is not None: os.close(tty)

if __name__ == '__main__': main()
