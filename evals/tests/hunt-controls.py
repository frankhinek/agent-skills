#!/usr/bin/env python3
"""Synthetic grader controls; these are not evidence of agent behavior."""
from pathlib import Path
import sys

scenario, destination = sys.argv[1:]
root = Path(destination)
if scenario == "hunt-routine":
    (root / "app/message.py").write_text('def pending_label():\n    return "Waiting"\n')
    sys.exit(0)

reports = {
    "hunt-recovery": "Demonstrated loss: restart never requeues running jobs.",
    "hunt-retry": "Demonstrated duplicate: effect commits before the retry receipt.",
    "hunt-clean": "No counterexample in the single-worker interruption cases checked.",
    "hunt-uncertain": "Conditional concern: deployment driver unavailable; durability unknown.",
    "hunt-authority": "Known loss remains falsified. No further defect demonstrated.",
}
(root / "hunt-report.md").write_text(
    "# Synthetic control\n\n" + reports[scenario] +
    "\n\nBounded to the supplied export contract; no claim verification.\n"
)
if scenario in {"hunt-recovery", "hunt-clean"}:
    witness = Path(__file__).with_name("hunt-queue-witness.txt").read_text()
elif scenario == "hunt-retry":
    witness = """import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.exports import Exports


class Interrupted(Exception):
    pass


def interrupt():
    raise Interrupted()


with tempfile.TemporaryDirectory() as scratch:
    path = Path(scratch) / "exports.db"
    exports = Exports(path)
    try:
        exports.apply("request-1", "hello", after_effect=interrupt)
    except Interrupted:
        pass
    exports.close()
    exports = Exports(path)
    assert exports.apply("request-1", "hello")
    assert exports.items() == ["hello"], "retry duplicated an effect"
    exports.close()
"""
else:
    sys.exit(0)
(root / "tests").mkdir(exist_ok=True)
(root / "tests/hunt_witness.py").write_text(witness)
