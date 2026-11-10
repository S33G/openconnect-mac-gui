#!/usr/bin/env python3
"""Native external-browser authentication; secrets travel only through pipes."""
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
from urllib.parse import urlsplit


def auth_command(executable, host, group):
    labels = host.split('.')
    if len(labels) < 2 or len(host) > 253 or not all(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', x) for x in labels):
        raise ValueError('invalid gateway')
    if len(group) > 80 or any(ord(c) < 32 or ord(c) == 127 for c in group) or group.startswith('-'):
        raise ValueError('invalid group')
    args = [executable, '--authenticate', '--non-inter', '--external-browser=/usr/bin/open',
            '--os=mac-intel', '--useragent=AnyConnect']
    if group: args += ['--authgroup', group]
    return args + [host]


def parse_auth(data):
    if len(data) > 65536: raise ValueError('oversize authentication response')
    fields = {}
    for line in data.decode('utf-8', 'strict').splitlines():
        # Parse shell quoting as data; never evaluate or execute this output.
        parts = shlex.split(line)
        if len(parts) != 1 or '=' not in parts[0]: continue
        key, value = parts[0].split('=', 1)
        if key in ('COOKIE', 'CONNECT_URL', 'FINGERPRINT', 'RESOLVE'):
            if key in fields: raise ValueError('duplicate authentication field')
            if any(ord(c) < 32 or ord(c) == 127 for c in value): raise ValueError('control character')
            fields[key] = value
    return validate_fields(fields)


def validate_fields(fields):
    if not isinstance(fields, dict) or any(not isinstance(k, str) or not isinstance(v, str) for k, v in fields.items()):
        raise ValueError('invalid authentication fields')
    if any(any(ord(c) < 32 or ord(c) == 127 for c in value) for value in fields.values()):
        raise ValueError('control character')
    if len(fields.get('COOKIE', '').encode('utf-8')) > 4095:
        raise ValueError('cookie too large')
    if not all(fields.get(k) for k in ('COOKIE', 'CONNECT_URL', 'FINGERPRINT')):
        raise ValueError('incomplete authentication response')
    url = urlsplit(fields['CONNECT_URL'])
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.fragment or url.query:
        raise ValueError('invalid connection URL')
    if not re.fullmatch(r'[A-Za-z0-9:+/=_-]{20,200}', fields['FINGERPRINT']):
        raise ValueError('invalid certificate fingerprint')
    if fields.get('RESOLVE') and not re.fullmatch(r'[A-Za-z0-9.:_-]{3,400}', fields['RESOLVE']):
        raise ValueError('invalid resolution hint')
    return fields


def tunnel_command(executable, fields, automatic, privileged=False):
    args = ([executable] if privileged else ['/usr/bin/sudo', '-n', executable]) + [ '--non-inter', '--cookie-on-stdin',
            '--servercert', fields['FINGERPRINT'], '--os=mac-intel', '--useragent=AnyConnect',
            '--reconnect-timeout', '300' if automatic else '1']
    if fields.get('RESOLVE'): args += ['--resolve', fields['RESOLVE']]
    return args + [fields['CONNECT_URL']]


def run(spec):
    print('Opening default browser for SSO', flush=True)
    with subprocess.Popen(auth_command(spec['openconnect'], spec['host'], spec['group']),
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE) as auth:
        # stderr goes to the supervisor's bounded discard-only lifecycle parser.
        data = auth.stdout.read(65537)
        if len(data) > 65536:
            auth.terminate()
            raise ValueError('oversize authentication response')
        code = auth.wait()
    if code:
        print('Authentication failed', flush=True)
        return code
    fields = parse_auth(data)
    data = b''
    if spec.get('runInBackground', False):
        payload = json.dumps(dict(sessionID=spec['sessionID'], openconnect=spec['openconnect'], autoReconnect=spec['autoReconnect'], fields=fields)).encode('utf-8')
        launcher = ['/usr/bin/sudo', '-n', sys.executable, '-I', '-S', '-B', str(Path(__file__).with_name('headless_tunnel.py')), str(Path(sys.argv[1]).parent)]
        return subprocess.run(launcher, input=payload).returncode
    cookie = fields.pop('COOKIE')
    print('Authentication successful', flush=True)
    # sudo was authorized directly in Terminal by the parent supervisor.
    # -n ensures this stage never prompts into a credential pipe.
    return subprocess.run(tunnel_command(spec['openconnect'], fields, spec['autoReconnect']),
                          input=cookie.encode('utf-8') + b'\n').returncode


if __name__ == '__main__':
    try:
        result = run(json.loads(Path(sys.argv[1]).read_text()))
    except KeyboardInterrupt:
        result = 130
    except Exception:
        # Neither exception details nor authentication fields may escape.
        print('Authentication failed', flush=True)
        result = 1
    sys.exit(result)
