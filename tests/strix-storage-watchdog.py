"""Exercise the evaluated probe under systemd without rebooting the test host.

Usage: python3 tests/strix-storage-watchdog.py EVALUATED_PROBE_SCRIPT
Requires passwordless sudo. Uses short deadlines and FailureAction=none.
"""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

temporary = tempfile.TemporaryDirectory(prefix='strix-watchdog-test-')
root = Path(temporary.name)
fixture = root / 'watchdog-probe-fixture'
script = root / 'watchdog-test-probe.sh'
source = Path(sys.argv[1]).read_text()
assert 'if probe; then' in source
source, count = re.subn(r'dd if=\S+ ', 'dd if=' + str(fixture) + ' ', source)
assert count == 1
source = source.replace('sleep 10', 'sleep 1')
script.write_text(source)

def run(*args):
    return subprocess.check_output(['sudo', '-n', *args], text=True).strip()

def prop(unit, key):
    return run('systemctl', 'show', unit, '--property=' + key, '--value')

results = []
for case in ['transient-error', 'persistent-error', 'blocked-process']:
    unit = 'strix-watchdog-test-' + root.name + '-' + case
    fixture.write_bytes(b'x' * 4096)
    try:
        run('systemd-run', '--unit=' + unit, '--property=Type=notify',
            '--property=NotifyAccess=all', '--property=WatchdogSec=4s',
            '--property=TimeoutStartSec=5s', '--property=TimeoutAbortSec=1s',
            '--property=TimeoutStopSec=1s', '--property=LimitCORE=0',
            '--property=FailureAction=none', '--property=Restart=no',
            '--setenv=PATH=/run/current-system/sw/bin',
            '/run/current-system/sw/bin/bash', str(script))
        time.sleep(1.2)
        assert prop(unit, 'ActiveState') == 'active'
        assert prop(unit, 'FailureAction') == 'none'
        before = prop(unit, 'WatchdogTimestampMonotonic')
        if case == 'blocked-process':
            run('systemctl', 'kill', '--signal=STOP', '--kill-whom=all', unit)
        else:
            fixture.unlink()
        if case == 'transient-error':
            time.sleep(1.2)
            fixture.write_bytes(b'x' * 4096)
            time.sleep(2.5)
            assert prop(unit, 'ActiveState') == 'active'
            assert int(prop(unit, 'WatchdogTimestampMonotonic')) > int(before)
            results.append({'case': case, 'result': 'healthy heartbeat resumed'})
        else:
            deadline = time.monotonic() + 9
            while prop(unit, 'ActiveState') != 'failed' and time.monotonic() < deadline:
                time.sleep(.2)
            assert prop(unit, 'ActiveState') == 'failed'
            result = prop(unit, 'Result')
            assert result == 'watchdog', result
            results.append({'case': case, 'result': result})
    finally:
        subprocess.run(['sudo', '-n', 'systemctl', 'kill', '--signal=CONT', unit], capture_output=True)
        subprocess.run(['sudo', '-n', 'systemctl', 'stop', unit], capture_output=True)
        subprocess.run(['sudo', '-n', 'systemctl', 'reset-failed', unit], capture_output=True)

fixture.unlink(missing_ok=True)
print(json.dumps(results, indent=2))
temporary.cleanup()
