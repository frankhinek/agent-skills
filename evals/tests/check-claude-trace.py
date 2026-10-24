"""Check trace extraction without spending model tokens or altering containment."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


adapter = Path(__file__).resolve().parents[1] / "trace-claude.py"
with tempfile.TemporaryDirectory(prefix="assurance-trace-") as directory:
    fake = Path(directory) / "claude"
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys
if '--version' in sys.argv:
    print('fake-claude 1.0')
    raise SystemExit(0)
assert sys.argv[sys.argv.index('--output-format') + 1] == 'stream-json'
assert '--verbose' in sys.argv
assert 'original prompt' in sys.argv
print(json.dumps({'type': 'assistant', 'message': {'content': [
    {'type': 'text', 'text': 'Fresh finding'},
    {'type': 'tool_use', 'name': 'Read', 'input': {'file_path': 'verification.md'}}]}}))
print('non-JSON diagnostic')
if os.environ.get('TRACE_TEST_EMPTY') != '1':
    print(json.dumps({'type': 'result', 'result': 'Final verdict'}))
raise SystemExit(int(os.environ.get('TRACE_TEST_EXIT', '0')))
''')
    fake.chmod(0o755)
    env = {**os.environ, "EVAL_CLAUDE_REAL_BIN": str(fake)}
    version = subprocess.run([sys.executable, str(adapter), "--version"], env=env,
                             capture_output=True, text=True, check=True)
    assert version.stdout == "fake-claude 1.0\n"
    command = [sys.executable, str(adapter), "-p", "original prompt", "--output-format", "text"]
    result = subprocess.run(command, env=env, capture_output=True, text=True, check=True)
    assert result.stdout == "Final verdict\n"
    assert result.stderr.index("Fresh finding") < result.stderr.index("verification.md")
    result = subprocess.run(command, env={**env, "TRACE_TEST_EXIT": "42"}, capture_output=True)
    assert result.returncode == 42
    result = subprocess.run(command, env={**env, "TRACE_TEST_EMPTY": "1"}, capture_output=True)
    assert result.stdout == b""  # The runner marks an empty response INVALID.
print("PASS: trace order, final response, version, and failure forwarding")
