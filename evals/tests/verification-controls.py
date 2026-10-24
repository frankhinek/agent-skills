"""Synthetic artifacts for grader controls; never evidence of agent behavior."""

from pathlib import Path
import sys


def prepare(scenario: str, root: Path) -> None:
    verdicts = {
        "verify-fresh": "falsified", "verify-valid": "pass",
        "verify-unavailable": "provisional", "composition-gap": "falsified",
        "witness-partial": "falsified", "witness-repaired": "provisional",
        "witness-unavailable": "falsified",
    }
    if scenario in ("witness-partial", "witness-repaired"):
        expr = "max(0, raw)" if scenario == "witness-partial" else "max(0, min(100, raw))"
        (root / "app/cache_policy.py").write_text(f"def ttl(raw):\n    return {expr}\n")
    slug = "cache-once" if scenario == "composition-gap" else "cache-ttl"
    path = root / f"specs/CLAIM-{slug}/verification.md"
    path.write_text(path.read_text() + f"""
Synthetic control: inspect this outcome only as a grader fixture.
tests/witness_ttl.py and tests/replay_ttl.py identify retained witnesses.
Result: {verdicts[scenario]}
""")


if __name__ == "__main__":
    prepare(sys.argv[1], Path(sys.argv[2]))
