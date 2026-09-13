#!/usr/bin/env python3
"""Persist scoped Plane auto-pickup and register its timer with XO's watcher.

Usage: xo-overwatch.py on [--slots 2] [--interval 300] [--max-pickups 10]
       xo-overwatch.py status|check|off
       xo-overwatch.py defer --outcome picked|empty|busy|error

Requires XO_HOME and its configured Plane adapter. No Plane/GitHub writes or
worker launches occur here. The Overwatch skill owns selection and dispatch.
The registered check emits a due event until Control records an outcome.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'bin'))
from xo_plane.cli import load_config
from xo_plane.registry import AdapterError


def save(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix='.overwatch-')
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(value, out)
            out.write('\n')
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['on', 'off', 'status', 'check', 'defer'])
    parser.add_argument('--slots', type=int, default=2)
    parser.add_argument('--interval', type=int, default=300)
    parser.add_argument('--max-pickups', type=int, default=10)
    parser.add_argument('--outcome', choices=['picked', 'empty', 'busy', 'error'])
    args = parser.parse_args()
    if not os.environ.get('XO_HOME'):
        raise AdapterError('XO_HOME must explicitly identify the Control home')
    home = Path(os.environ['XO_HOME']).resolve()
    state = Path(os.environ.get('XO_STATE_OVERRIDE', str(home / 'state')))
    if state.is_symlink():
        raise AdapterError('state directory must not be a symlink')
    state.mkdir(parents=True, exist_ok=True)
    policy_path = state / 'overwatch.json'
    lock_path = state / '.overwatch.lock'
    if policy_path.is_symlink() or lock_path.is_symlink():
        raise AdapterError('unsafe Overwatch state path')
    config_path = home / 'config/plane.json'
    with open(lock_path, 'a') as lock:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        policy = json.loads(policy_path.read_text()) if policy_path.exists() else {'enabled': False}
        now = int(time.time())
        env = dict(os.environ, XO_HOME=str(home), XO_STATE_OVERRIDE=str(state))
        if args.command == 'on':
            if args.slots < 1 or args.interval < 60 or args.max_pickups < 1:
                raise AdapterError('slots/pickup budget must be positive; interval must be at least 60 seconds')
            config = load_config(config_path)
            if policy.get('enabled'):
                raise AdapterError('Overwatch is already enabled; inspect status or turn it off before replacing scope')
            shim = state / 'overwatch.check.sh'
            if shim.exists() or shim.is_symlink():
                raise AdapterError('existing Overwatch check needs off/reconciliation before enabling')
            policy = {'enabled': True, 'project_id': config['project_id'],
                      'repository_url': config['repository_url'], 'executor': config['executor'],
                      'config_sha256': hashlib.sha256(config_path.read_bytes()).hexdigest(),
                      'slots': args.slots, 'interval': args.interval, 'max_pickups': args.max_pickups,
                      'picked': 0, 'empty_streak': 0, 'next_check': now}
            # The check has fixed, quoted paths; Plane contents never become shell code.
            command = shlex.join([sys.executable, str(Path(__file__).resolve()), 'check'])
            content = '#!/bin/sh\nexec env ' + shlex.join(['XO_HOME=' + str(home), 'XO_STATE_OVERRIDE=' + str(state)]) + ' ' + command + '\n'
            fd = os.open(shim, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o700)
            with os.fdopen(fd, 'w') as out:
                out.write(content)
            result = subprocess.run([str(ROOT / 'bin/xo-check-register.sh'), 'overwatch'], env=env, capture_output=True)
            if result.returncode:
                raise AdapterError('check registration failed; Overwatch remains disabled; reconcile with off')
            save(policy_path, policy)
        elif args.command == 'off':
            policy['enabled'] = False
            save(policy_path, policy)
            result = subprocess.run([str(ROOT / 'bin/xo-check-unregister.sh'), 'overwatch'], env=env, capture_output=True)
            if result.returncode:
                raise AdapterError('pickup disabled but check retirement needs reconciliation')
        elif args.command == 'check':
            if not policy.get('enabled'):
                return
            if not config_path.exists() or hashlib.sha256(config_path.read_bytes()).hexdigest() != policy['config_sha256']:
                print('overwatch: configuration changed; pause and reconcile before pickup')
            elif policy['picked'] >= policy['max_pickups']:
                print('overwatch: pickup budget reached; turn off and report')
            elif now >= policy['next_check']:
                print('overwatch: pickup check due; load overwatch skill')
            return
        elif args.command == 'defer':
            if not policy.get('enabled') or not args.outcome:
                raise AdapterError('defer requires enabled Overwatch and an outcome')
            if args.outcome == 'picked':
                policy['picked'] += 1
            policy['empty_streak'] = min(policy['empty_streak'] + 1, 4) if args.outcome == 'empty' else 0
            policy['next_check'] = now + min(policy['interval'] * (2 ** policy['empty_streak']), 3600)
            if args.outcome == 'error':
                policy['enabled'] = False
            save(policy_path, policy)
        print(json.dumps(policy, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (AdapterError, OSError, ValueError, KeyError) as exc:
        # Do not print private config values or subprocess/transport output.
        print('Overwatch operation failed: inspect configuration and registered check state.', file=sys.stderr)
        sys.exit(1)
