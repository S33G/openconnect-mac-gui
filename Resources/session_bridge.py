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


def classify(line):
    # Parse lifecycle messages only. Everything else is discarded.
    text = line.lower()
    if 'server certificate verify failed' in text or 'certificate verification failed' in text:
        return 'certificate_failed'
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


def command(sso, host, group, automatic):
    labels = host.split('.')
    if len(labels) < 2 or len(host) > 253 or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', x) for x in labels):
        raise ValueError('invalid gateway')
    if len(group) > 80 or any(ord(c) < 32 or ord(c) == 127 for c in group) or group.startswith('-'):
        raise ValueError('invalid group')
    args = [sso, '--server', host, '--browser-display-mode', 'shown']
    if group:
        args += ['--authgroup', group]
    # openconnect-sso 0.8.1 consumes the first remainder argument as a program label.
    return args + ['--', 'openconnect', '--reconnect-timeout', '300' if automatic else '1']


def environment(root, openconnect):
    config = root / 'config'
    folder = config / 'openconnect-sso'
    folder.mkdir(parents=True, mode=0o700, exist_ok=True)
    config.chmod(0o700)
    target = folder / 'config.toml'
    target.write_text('auto_fill_rules = {}\n')
    target.chmod(0o600)
    # Keep GUI/session variables, remove Python and Qt injection overrides.
    env = {k: v for k, v in os.environ.items() if not k.startswith(('PYTHON', 'QT_', 'XDG_', 'LD_', 'DYLD_'))}
    home = root / 'home'
    home.mkdir(mode=0o700, exist_ok=True)
    env.update(HOME=str(home), CFFIXED_USER_HOME=str(home), PATH=str(Path(openconnect).parent) + ':/usr/bin:/bin:/usr/sbin:/sbin',
               LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8',
               PYTHON_KEYRING_BACKEND='keyring.backends.null.Keyring',
               XDG_CONFIG_HOME=str(config), XDG_CONFIG_DIRS=str(config),
               XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'))
    return env


def status(root, session, phase, finished=False):
    target = root / 'status.tmp'
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(dict(sessionID=session, phase=phase, updatedAt=time.time(), finished=finished), stream)
    os.replace(target, root / 'status.json')


def group_alive(pid):
    try:
        os.killpg(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def supervise(args, root, env, session, tty, phase='needs_sso', interactive=False):
    """Return the exit code only after the owned process group has gone away."""
    proc = subprocess.Popen(args, env=env, stdin=None if interactive else subprocess.DEVNULL,
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
    try:
        selector = selectors.DefaultSelector()
        if tty is not None:
            previous = os.tcgetpgrp(tty)
            os.tcsetpgrp(tty, proc.pid)
        if proc.stdout:
            os.set_blocking(proc.stdout.fileno(), False)
            selector.register(proc.stdout, selectors.EVENT_READ)
        while True:
            now = time.monotonic()
            try:
                owner_lost = time.time() - (root / 'owner').stat().st_mtime > 20
            except FileNotFoundError:
                owner_lost = True
            expired = not had_tunnel and now - started > 180
            if stopped is None and ((root / 'stop').exists() or owner_lost or expired):
                stopped = now
                if expired:
                    failure = 'sign_in_timeout'
                phase = 'disconnecting'
                try: os.killpg(proc.pid, signal.SIGINT)
                except (ProcessLookupError, PermissionError): pass
            if stopped is not None and now - stopped > 12:
                phase = 'disconnect_stuck'
            if now - heartbeat > 0.5:
                status(root, session, phase)
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
                        if observed.endswith('_failed'): failure = observed
                        phase = observed
                        had_tunnel = had_tunnel or observed == 'connected'
            if interactive:
                time.sleep(0.1)
            code = proc.poll()
            if code is not None and not group_alive(proc.pid):
                final = failure or ('stopped' if stopped is not None else ('exited' if code == 0 else 'session_failed'))
                status(root, session, final, finished=not interactive)
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
            try: status(root, session, 'disconnect_stuck')
            except OSError: pass
            time.sleep(0.5)
        status(root, session, 'session_failed', finished=not interactive)
        return -1
    finally:
        if selector is not None: selector.close()
        if proc.stdout: proc.stdout.close()
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
        (root / 'stop').touch()
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(sig, stop)
    try:
        tty = os.open('/dev/tty', os.O_RDWR)
        args = command(spec['sso'], spec['host'], spec['group'], spec['autoReconnect'])
        env = environment(root, spec['openconnect'])
        print('Betterer Connect needs administrator access to create the VPN tunnel.\nEnter your Mac password at the sudo prompt. Browser sign-in follows.\nKeep this window open until disconnected.', flush=True)
        status(root, session, 'permission')
        if supervise(['/usr/bin/sudo', '-v'], root, env, session, tty, 'permission', True) != 0:
            prior = json.loads((root / 'status.json').read_text())['phase']
            final = prior if prior in ('stopped', 'sign_in_timeout') else 'permission_failed'
            status(root, session, final, True)
            return
        if (root / 'stop').exists():
            status(root, session, 'stopped', True)
            return
        print('Complete sign-in in the browser window. Use Betterer Connect to disconnect.', flush=True)
        supervise(args, root, env, session, tty)
        print('VPN session ended. You can close this Terminal window.', flush=True)
    except Exception:
        # Never print exception details: library exceptions can contain credentials.
        status(root, session, 'session_failed', True)
        print('Session could not start. Return to Betterer Connect for the safe status code.', flush=True)
    finally:
        if tty is not None: os.close(tty)

if __name__ == '__main__': main()
