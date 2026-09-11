"""Shared claims in a dedicated Git ref per Plane item.

Each write uses an explicit expected remote SHA. An empty expectation creates
only an absent ref. Never delete claim history or retry a competing write as
if it succeeded. A lost push response is recoverable by reading the record.
"""

import hashlib
import json
import os
import subprocess
import tempfile
from pathlib import Path


class AdapterError(Exception):
    pass


class Registry:
    def __init__(self, remote, key):
        if not isinstance(remote, str) or not remote or remote.startswith("-"):
            raise AdapterError("invalid coordination remote")
        self.remote = remote
        self.ref = "refs/heads/fm-plane/" + hashlib.sha256(key.encode()).hexdigest()
        self.tmp = tempfile.TemporaryDirectory(prefix="fm-plane-")
        self.path = Path(self.tmp.name)
        self.git("init", "--bare", "-q")
        self.git("remote", "add", "origin", remote)

    def close(self):
        self.tmp.cleanup()

    def git(self, *args, input=None, allow_failure=False):
        env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        # Registry commits are operational records, never product commits.
        env.update(GIT_AUTHOR_NAME="Team coordination", GIT_AUTHOR_EMAIL="coordination@localhost",
                   GIT_COMMITTER_NAME="Team coordination", GIT_COMMITTER_EMAIL="coordination@localhost")
        result = subprocess.run(["git", "-C", str(self.path), *args], input=input,
                                text=True, capture_output=True, timeout=45, env=env)
        if result.returncode and not allow_failure:
            # Git diagnostics may echo credential-bearing remote URLs.
            raise AdapterError("coordination Git operation failed; check access and connectivity")
        return result

    def read(self):
        result = self.git("ls-remote", "--exit-code", "origin", self.ref, allow_failure=True)
        if result.returncode == 2:
            return "", None
        if result.returncode:
            raise AdapterError("cannot read shared claim; no local fallback")
        self.git("fetch", "--quiet", "--no-tags", "origin", self.ref)
        sha = self.git("rev-parse", "FETCH_HEAD").stdout.strip()
        try:
            record = json.loads(self.git("show", "FETCH_HEAD:claim.json").stdout)
            if record["schema"] != 1 or not isinstance(record["execution"], str):
                raise ValueError()
        except (ValueError, KeyError, TypeError) as exc:
            raise AdapterError("malformed shared claim; reconcile before proceeding") from exc
        return sha, record

    def write(self, expected, record):
        blob = self.git("hash-object", "-w", "--stdin",
                        input=json.dumps(record, sort_keys=True) + "\n").stdout.strip()
        tree = self.git("mktree", input=f"100644 blob {blob}\tclaim.json\n").stdout.strip()
        parents = ["-p", expected] if expected else []
        commit = self.git("commit-tree", tree, *parents,
                          input="Update Plane execution record\n").stdout.strip()
        result = self.git("push", "--quiet", f"--force-with-lease={self.ref}:{expected}",
                          "origin", f"{commit}:{self.ref}", allow_failure=True)
        if result.returncode:
            _, current = self.read()
            if current != record:
                raise AdapterError("claim changed concurrently; reread before proceeding")
        return record
