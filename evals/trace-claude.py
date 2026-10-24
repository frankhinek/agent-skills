#!/usr/bin/env python3
"""Optional Claude CLI adapter: retain tool-call order in the runner's log."""

import json
import os
import subprocess
import sys


def main() -> int:
    real = os.environ["EVAL_CLAUDE_REAL_BIN"]
    args = sys.argv[1:]
    if "--version" in args:
        os.execv(real, [real, *args])
    index = args.index("--output-format")
    args[index + 1] = "stream-json"
    args.append("--verbose")
    result = None
    with subprocess.Popen([real, *args], stdout=subprocess.PIPE, text=True) as child:
        for line in child.stdout:
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get("type") == "assistant":
                for block in event.get("message", {}).get("content", []):
                    if block.get("type") in ("tool_use", "text"):
                        print("TRACE " + json.dumps(block), file=sys.stderr, flush=True)
            if event.get("type") == "result":
                result = event.get("result")
        code = child.wait()
    if isinstance(result, str):
        print(result)
    return code


if __name__ == "__main__":
    sys.exit(main())
