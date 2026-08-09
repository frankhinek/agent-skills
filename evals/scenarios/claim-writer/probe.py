#!/usr/bin/env python3
"""Classify save_note persistence without trusting source spellings."""

import ast
import importlib
import json
import os
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, os.getcwd())


def call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = call_name(node.value)
        return f"{prefix}.{node.attr}" if prefix else node.attr
    return ""


def constant_string(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    return None


def open_mode(call, attribute_call):
    position = 0 if attribute_call else 1
    if len(call.args) > position:
        return constant_string(call.args[position])
    for keyword in call.keywords:
        if keyword.arg == "mode":
            return constant_string(keyword.value)
    return "r"


class DirectWriteVisitor(ast.NodeVisitor):
    def __init__(self, path):
        self.path = path
        self.os_mutators = {"replace", "rename"}
        self.hits = []

    def visit_ImportFrom(self, node):
        if node.module == "os":
            for alias in node.names:
                if alias.name in {"open", "replace", "rename"}:
                    self.os_mutators.add(alias.asname or alias.name)
        self.generic_visit(node)

    def visit_Call(self, node):
        name = call_name(node.func)
        attribute_call = isinstance(node.func, ast.Attribute)
        direct = False

        if name in {"os.open", "os.replace", "os.rename"}:
            direct = True
        elif name in self.os_mutators:
            direct = True
        elif name.endswith((".write_text", ".write_bytes")):
            direct = True
        elif name == "open" or name.endswith(".open"):
            mode = open_mode(node, attribute_call)
            direct = mode is None or any(flag in mode for flag in "wax+")

        if direct:
            self.hits.append(f"{self.path}:{node.lineno}: {name or 'write call'}")
        self.generic_visit(node)


def production_python(path):
    parts = Path(path).parts
    if Path(path).suffix != ".py":
        return False
    if path == "app/store.py":
        return False
    return not any(part in {".agents", "specs", "test", "tests"} for part in parts)


def direct_write_hits(paths):
    hits = []
    for name in paths:
        if not production_python(name):
            continue
        path = Path(name)
        if not path.is_file():
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=name)
        except (OSError, UnicodeError, SyntaxError) as error:
            raise RuntimeError(f"could not inspect {name}: {error}") from error
        visitor = DirectWriteVisitor(name)
        visitor.visit(tree)
        hits.extend(visitor.hits)
    return hits


def observe_save_note():
    note_id = f"f11-probe-{os.getpid()}"
    expected_key = "note-" + note_id
    expected_value = {"text": "f11 probe"}
    target = Path("data") / f"{expected_key}.json"
    calls = []

    def observe(_store, key, value):
        calls.append((key, value))

    if target.exists():
        target.unlink()

    try:
        store_module = importlib.import_module("app.store")
        with patch.object(store_module.Store, "write", observe):
            handler = importlib.import_module("app.handler")
            handler.save_note(note_id, expected_value["text"])
        direct_value = json.loads(target.read_text()) if target.exists() else None
    except Exception as error:  # The checker must report, not mask, subject failures.
        raise RuntimeError(f"{type(error).__name__}: {error}") from error
    finally:
        if target.exists():
            target.unlink()
        try:
            target.parent.rmdir()
        except OSError:
            pass

    exact_delegation = calls == [(expected_key, expected_value)]
    direct_persistence = direct_value == expected_value
    if exact_delegation and not direct_persistence:
        return "delegated"
    if not calls and direct_persistence:
        return "direct"
    if calls and direct_persistence:
        return "mixed"
    raise RuntimeError(
        f"unexpected outcome (Store.write calls={calls!r}, direct value={direct_value!r})"
    )


def main():
    try:
        behavior = observe_save_note()
    except RuntimeError as error:
        print(f"FAIL: save_note behavior could not be checked: {error}")
        return 2

    try:
        hits = direct_write_hits(sys.argv[1:])
    except RuntimeError as error:
        print(f"FAIL: direct-write heuristics could not be evaluated: {error}")
        return 2

    if behavior == "delegated":
        print("PASS: save_note delegated the expected note through Store.write")
    elif behavior == "direct":
        print("OBSERVED: save_note persisted the expected note without Store.write")
    else:
        print("OBSERVED: save_note invoked Store.write and also persisted directly")

    for hit in hits:
        print(f"HEURISTIC: direct-write API in changed production code: {hit}")

    if behavior == "direct":
        return 10
    if behavior == "mixed":
        return 11
    if hits:
        return 12
    return 0


if __name__ == "__main__":
    sys.exit(main())
