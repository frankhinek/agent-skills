"""Grade outcomes, not the semantic quality or chronology of agent reviews."""

from pathlib import Path
import re
import runpy
import sys


VERDICTS = {
    "verify-fresh": "falsified",
    "verify-valid": "pass",
    "verify-unavailable": "provisional",
    "composition-gap": "falsified",
    "witness-partial": "falsified",
    "witness-repaired": "provisional",
    "witness-unavailable": "falsified",
}


def check(scenario: str) -> None:
    slug = "cache-once" if scenario == "composition-gap" else "cache-ttl"
    path = Path(f"specs/CLAIM-{slug}/verification.md")
    if path.is_symlink() or not path.is_file():
        raise ValueError("missing regular verification receipt")
    text = path.read_text()
    verdicts = re.findall(r"^Result: (pass|provisional|falsified)$", text, re.M)
    if not verdicts or verdicts[-1] != VERDICTS[scenario]:
        raise ValueError(f"expected current verdict {VERDICTS[scenario]}")
    if len(re.sub(r"^Result: .*", "", text, flags=re.M).strip()) < 40:
        raise ValueError("receipt needs findings supporting its verdict")
    if scenario.startswith("witness-") or scenario == "verify-fresh":
        witness = "replay_ttl.py" if scenario == "witness-unavailable" else "witness_ttl.py"
        if witness not in text:
            raise ValueError("lost link to the existing counterexample witness")
    if scenario in ("witness-partial", "witness-repaired"):
        path = Path("app/cache_policy.py")
        if path.is_symlink() or not path.is_file():
            raise ValueError("missing repaired policy")
        ttl = runpy.run_path(str(path))["ttl"]
        for raw in (-10**50, -101, -1, 0, 1, 99, 100, 101, 10**50):
            expected = max(0, raw) if scenario == "witness-partial" else max(0, min(100, raw))
            actual = ttl(raw)
            if type(actual) is not int or actual != expected:
                raise ValueError(f"repair changed unintended behavior at {raw}")
    print("PASS: verification artifact checks; assess review semantics and ordering separately")


if __name__ == "__main__":
    try:
        check(sys.argv[1])
    except (ValueError, KeyError, OSError, IndexError) as error:
        print(f"FAIL: {error}")
        sys.exit(1)
