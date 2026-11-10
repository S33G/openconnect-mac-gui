#!/usr/bin/env python3
"""Per-session privileged supervisor. No service installation or saved secrets."""
import json
import os
from pathlib import Path
import pwd
import signal
import sys
import uuid

# Root entry runs Python with -I -S; load only the adjacent bundled modules.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from session_bridge import Runtime, status, supervise
from openconnect_auth import validate_fields, tunnel_command


def validate_executable(value):
    if value not in ('/opt/homebrew/bin/openconnect', '/usr/local/bin/openconnect') or not os.access(value, os.X_OK):
        raise ValueError('unsupported executable')
    return value


def detach(root, session, args, env, cookie, owner):
    """Return to the launcher only after forking; safe status owns completion."""
    runtime = Runtime(root, owner=owner)
    ready_read, ready_write = os.pipe()
    commit_read, commit_write = os.pipe()
    child = os.fork()
    if child:
        os.close(ready_write); os.close(commit_read)
        try:
            if os.read(ready_read, 1) != b'1': raise RuntimeError('background startup not acknowledged')
            os.write(commit_write, b'1')
        finally:
            os.close(ready_read); os.close(commit_write); runtime.__exit__()
        return
    os.close(ready_read); os.close(commit_write)
    try:
        os.setsid()
        if os.fork(): os._exit(0)
        os.chdir('/')
        os.umask(0o077)
        null = os.open('/dev/null', os.O_RDWR)
        for fd in (0, 1, 2): os.dup2(null, fd)
        if null > 2: os.close(null)
        def stop(_sig, _frame): runtime.request_stop()
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(sig, stop)
        status(runtime, session, 'connecting')
        runtime.write_json('detached.json', dict(sessionID=session, detached=True))
        os.write(ready_write, b'1'); os.close(ready_write)
        if os.read(commit_read, 1) != b'1':
            status(runtime, session, 'stopped', True)
            return
        os.close(commit_read)
        if runtime.exists('stop') or runtime.owner_lost():
            status(runtime, session, 'stopped', True)
            return
        supervise(args, runtime, env, session, None, phase='connecting', stdin_data=cookie)
    except BaseException:
        # supervise owns child teardown on its own error paths before returning.
        try: status(runtime, session, 'session_failed', True)
        except OSError: pass
    finally:
        runtime.__exit__()
        os._exit(0)


def main():
    if os.geteuid() != 0: raise ValueError('administrator access required')
    uid, gid = int(os.environ['SUDO_UID']), int(os.environ['SUDO_GID'])
    if uid <= 0 or gid < 0: raise ValueError('invalid user')
    root = Path(sys.argv[1])
    home = Path(pwd.getpwuid(uid).pw_dir)
    expected = home / 'Library/Application Support/OpenConnect Mac GUI/Sessions'
    if root.parent.resolve() != expected.resolve() or str(uuid.UUID(root.name)).upper() != root.name.upper():
        raise ValueError('invalid session location')
    data = sys.stdin.buffer.read(65537)
    if len(data) > 65536: raise ValueError('oversize launch payload')
    payload = json.loads(data)
    if payload['sessionID'].upper() != root.name.upper(): raise ValueError('session mismatch')
    executable = validate_executable(payload['openconnect'])
    fields = validate_fields(payload['fields'])
    cookie = fields.pop('COOKIE').encode('utf-8') + b'\n'
    args = tunnel_command(executable, fields, payload['autoReconnect'] is True, privileged=True)
    env = dict(PATH='/usr/bin:/bin:/usr/sbin:/sbin', HOME='/var/root', LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8')
    detach(root, payload['sessionID'], args, env, cookie, (uid, gid))


if __name__ == '__main__':
    try: main()
    except Exception:
        print('Background startup failed', flush=True)
        sys.exit(1)
