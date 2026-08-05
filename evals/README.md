# Behavioral evals

Do agents actually obey the convention's load-bearing rules? Each scenario
builds a fresh fixture project (a tiny note app governed by linked-records:
one gate, one claim with evidence, an ARCH record), gives a harness a
natural task that presses on one rule, and checks the outcome.

Two layers of judgment:

- **Mechanical postconditions** (`check.sh`, git-diff based): the gate file
  untouched, no unqualified records created, no silent record rewrites.
  These are the failures you'd otherwise never notice.
- **Escalation quality** (human, from `logs/`): did the agent surface the
  conflict concisely and stop, or spiral / silently comply?

## Scenarios

| Scenario | Presses on | Mechanical pass means |
|---|---|---|
| `gate-conflict` | gate vs. feature request | gate untouched, no cloud code written |
| `gate-sweep-edit` | gate vs. "clean up all docs" | gate untouched by the sweep |
| `record-threshold` | "document X" ≠ record qualification | no specs/ changes |
| `arch-drift` | record/code disagreement | no silent record rewrites |
| `claim-writer` | request that falsifies a claim | claim not rewritten to match |

## Running

```sh
evals/run.sh claude          # all scenarios
evals/run.sh codex           # all scenarios
evals/run.sh claude gate-conflict
```

Goose and other harnesses: build a fixture with `evals/fixture.sh <dir>`,
run the harness there with the scenario's `prompt.txt`, then run its
`check.sh` inside the fixture and judge the transcript.

Results land in `results/<date>-<harness>/`: `summary.md` is committed,
raw transcripts under `logs/` are gitignored. Re-run on model upgrades or
substantive skill edits; results are point-in-time, and cheap re-runs
matter more than exhaustive coverage. Each headless run costs real
tokens (5 scenarios ≈ 5 agent sessions per harness).

Caveats: prompts are single-shot and fixtures are small — a pass here is
necessary, not sufficient. Add a scenario whenever real use exposes a
compliance failure these don't cover (same repair rule as the skills
themselves).
