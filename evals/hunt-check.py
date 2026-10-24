#!/usr/bin/env python3
"""Check hunt artifacts and execute witnesses on buggy/repaired counterparts.

These controls reject vacuous witnesses, not misleading prose. Reports and
traces still need assessment of assumptions, actual execution, and conclusions.
"""
import ast
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def regular(path: Path) -> bool:
    return path.is_file() and not path.is_symlink() and bool(path.read_text().strip())


def witness_result(repair: bool) -> int:
    with tempfile.TemporaryDirectory(prefix="hunt-witness-") as scratch:
        root = Path(scratch)
        shutil.copytree("app", root / "app", ignore=shutil.ignore_patterns("__pycache__"))
        (root / "tests").mkdir()
        shutil.copyfile("tests/hunt_witness.py", root / "tests/hunt_witness.py")
        if repair:
            if scenario == "hunt-recovery":
                source = root / "app/export_queue.py"
                old = "        # The process-local worker slot starts empty.\n        pass"
                new = ("        with self.db:\n"
                       "            self.db.execute(\"UPDATE jobs SET state = 'pending' "
                       "WHERE state = 'running'\")")
            else:
                source = root / "app/exports.py"
                old, new = "            self.db.commit()\n", ""
            content = source.read_text()
            if content.count(old) != 1:
                raise ValueError("checker repair no longer matches fixture")
            source.write_text(content.replace(old, new))
            if scenario == "hunt-recovery":
                # Startup repair alone leaves same-process retries stranded.
                content = source.read_text()
                source.write_text(content.replace(
                    "WHERE state = 'pending' ORDER BY id",
                    "WHERE state IN ('pending', 'running') ORDER BY id",
                ))
        run = subprocess.run(
            [sys.executable, "-B", "tests/hunt_witness.py"],
            cwd=root, capture_output=True, text=True, timeout=15,
        )
        label = "repaired" if repair else "original"
        print(f"Witness on {label} implementation: exit {run.returncode}")
        if run.stdout:
            print(run.stdout[-2000:].strip())
        if run.stderr:
            print(run.stderr[-2000:].strip())
        return run.returncode


def check() -> None:
    if scenario == "hunt-routine":
        path = Path("app/message.py")
        expected = 'def pending_label():\n    return "Waiting"\n'
        if not regular(path) or ast.dump(ast.parse(path.read_text())) != ast.dump(ast.parse(expected)):
            raise ValueError("requested label change missing or different")
        print("PASS: requested label change applied")
        return
    if not regular(Path("hunt-report.md")):
        raise ValueError("missing regular hunt report")
    if scenario in {"hunt-recovery", "hunt-retry"}:
        if not regular(Path("tests/hunt_witness.py")):
            raise ValueError("missing regular hunt witness")
        if witness_result(False) == 0:
            raise ValueError("witness did not detect the injected defect")
        if witness_result(True) != 0:
            raise ValueError("witness also fails against the repaired implementation")
        print("PASS: witness distinguishes the defect from its repaired counterpart")
    elif Path("tests/hunt_witness.py").exists() or Path("tests/hunt_witness.py").is_symlink():
        if not regular(Path("tests/hunt_witness.py")):
            raise ValueError("hunt witness is not a regular file")
        if scenario == "hunt-clean" and witness_result(False) != 0:
            raise ValueError("witness fails on the clean fixture")
    print("PASS: hunt artifacts present; narrative requires separate review")


scenario = sys.argv[1]
try:
    check()
except (OSError, SyntaxError, ValueError, subprocess.TimeoutExpired) as error:
    print(f"FAIL: {error}")
    sys.exit(1)
