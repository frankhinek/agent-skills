"""Grade artifact boundaries and verdicts; prose semantics need human review."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


def regular(path: str) -> bool:
    candidate = Path(path)
    return candidate.is_file() and not candidate.is_symlink()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def provisional(slug: str) -> None:
    path = f"specs/CLAIM-{slug}/verification.md"
    require(regular(path), f"missing regular verification for {slug}")
    text = Path(path).read_text()
    results = re.findall(r"^Result: (pass|provisional|falsified)$", text, re.M)
    require(bool(results) and results[-1] == "provisional",
            f"{slug} requires provisional evidence, not pass or falsified")
    require(len(text.replace("Result: provisional", "").strip()) > 20,
            f"{slug} lacks an explanation for its verdict")


def check(scenario: str) -> None:
    model = {
        "formal-local": "identity", "formal-proof": "clamp",
        "formal-mismatch": "lower", "formal-staleness": "reservation",
        "claim-composition": "reservation",
        "claim-residual": "posting",
    }[scenario]
    require(regular(f"verification/{model}.smt2"), "formal fixture is incomplete")
    if scenario == "formal-local":
        path = "verification/identity.smt2"
        baseline = subprocess.check_output(
            ["git", "show", f"{os.environ['EVAL_BASE']}:{path}"], text=True)
        def executable(text: str) -> list[str]:
            return re.sub(r";[^\n]*", "", text).split()
        require(executable(Path(path).read_text()) == executable(baseline),
                "identity executable verification changed")
    elif scenario == "formal-proof":
        path = "specs/CLAIM-score-export/proof.md"
        require(regular(path), "missing formal evidence argument")
        text = Path(path).read_text()
        for signal in (r"(?:`formal`|\*\*formal\*\*|\bformal\s*[:—–-])", r"clamp_bounds", r"verification/clamp[.]smt2",
                       r"\bz3\b", r"5[.]3[.]1", r"\bunsat\b", r"\bcode\b",
                       r"app/score[.]py", r"app/score_export[.]py"):
            require(bool(re.search(signal, text, re.I)),
                    f"formal evidence lacks required artifact signal: {signal}")
    elif scenario == "formal-mismatch":
        provisional("score-export")
    elif scenario == "formal-staleness":
        require(regular("config/storage.json"), "storage configuration is missing")
        require(json.loads(Path("config/storage.json").read_text()) == {"driver": "candidate-v2"},
                "requested storage selection is not exact")
        for slug in ("reservation", "single-post", "retry-safe"):
            provisional(slug)
            require(regular(f"specs/CLAIM-{slug}/proof.md"), f"lost proof for {slug}")
    elif scenario == "claim-composition":
        provisional("delivery")
    elif scenario == "claim-residual":
        provisional("posting-durability")
    print("PASS: formal scenario artifact checks; review evidence and response semantics")


if __name__ == "__main__":
    try:
        check(sys.argv[1])
    except (ValueError, KeyError, OSError, IndexError) as error:
        print(f"FAIL: {error}")
        sys.exit(1)
