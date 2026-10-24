"""Synthetic compliant artifacts for grader and fake-runner controls only."""

from pathlib import Path
import subprocess
import sys


def prepare(scenario: str, root: Path) -> None:
    def write(relative: str, text: str) -> None:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def verdict(slug: str, reason: str) -> None:
        write(f"specs/CLAIM-{slug}/verification.md", reason + "\nResult: provisional\n")

    if scenario == "formal-proof":
        revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
        write("specs/CLAIM-score-export/proof.md", f"""## Scope
app/score.py, app/score_export.py, verification/clamp.smt2 at {revision}.
## Model and quantifiers
All mathematical integer inputs; Python integers correspond to these values.
## Axioms
Z3 5.3.1, SMT integer semantics, the encoding, and Python JSON integer round-trip.
## Argument
1. `formal` — clamp_bounds in [SMT source](../../verification/clamp.smt2).
   Command: z3 verification/clamp.smt2. Reference result: unsat.
   The separate model's clamp returns an integer in [0,100] for every integer.
2. `code` — app/score.py implements the same three cases using min/max.
3. `code` — app/score_export.py serializes clamp_score(raw) without changing it.
   This correspondence is reviewed, not established by the SMT solver.
## Residuals
Non-integer inputs are outside the stated quantifiers.
## Weakest links
Production correspondence and JSON behavior remain outside the formal check.
""")
    elif scenario == "formal-mismatch":
        verdict("score-export", "clamp_nonnegative establishes only the lower bound. The supplied formal argument lacks the upper bound and exporter correspondence; no claim counterexample is established.")
    elif scenario == "formal-staleness":
        write("config/storage.json", '{"driver": "candidate-v2"}\n')
        reasons = {
            "reservation": "config/storage.json selects candidate-v2, whose atomicity is unassessed. The unchanged model still relies on the certified-v1 correspondence. Establish the new driver guarantee before re-verification.",
            "single-post": "CLAIM-reservation lost support; the driver transaction assumption also needs reassessment. Recheck the imported conclusion and connecting argument before restoring pass.",
            "retry-safe": "CLAIM-single-post is provisional through CLAIM-reservation. Recheck that dependency chain and retry correspondence before restoring pass.",
        }
        for slug, reason in reasons.items():
            verdict(slug, reason)
    elif scenario == "claim-composition":
        verdict("delivery", "CLAIM-exclusive assumes single-worker while CLAIM-failover assumes multi-worker. Their conditional passes do not establish the conjunction in one deployment. A compatible composition argument is missing; no production counterexample is available.")
    elif scenario == "claim-residual":
        verdict("posting-durability", "The passing model assumes orderly shutdown, excluding the abrupt process termination named by the claim. Its author's residual acceptance has no user authorization. The existing power-loss exclusion and storage contract already have support. Retain the claim and seek a decision on the uncovered crash behavior; no production counterexample is established.")
    elif scenario != "formal-local":
        raise ValueError(scenario)


if __name__ == "__main__":
    prepare(sys.argv[1], Path(sys.argv[2]))
