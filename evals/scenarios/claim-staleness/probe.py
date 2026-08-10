#!/usr/bin/env python3
import importlib
import json
import sys
import tempfile
from pathlib import Path


def main():
    sys.path.insert(0, str(Path.cwd()))
    store_module = importlib.import_module("app.store")
    with tempfile.TemporaryDirectory(prefix="linked-records-staleness-") as tmp:
        store_module.DATA_DIR = tmp
        store_module.Store().write("ordering", {"z": 1, "a": 2})
        raw = (Path(tmp) / "ordering.json").read_text()

    parsed = json.loads(raw)
    if parsed != {"a": 2, "z": 1}:
        print("FAIL: Store.write changed the stored JSON value")
        return 10
    if raw.find('"a"') < raw.find('"z"'):
        print("PASS: Store.write sorts JSON object keys")
        return 0

    print("FAIL: Store.write did not sort JSON object keys")
    return 11


if __name__ == "__main__":
    raise SystemExit(main())
