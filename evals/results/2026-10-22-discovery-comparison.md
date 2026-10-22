---
summary: "Records before/after discovery evals, successful negative controls, and the limits of the evidence."
read_when:
  - Assessing the affected-record discovery procedure
  - Repeating discovery evals after skill or model changes
title: "Record Discovery Comparison — 2026-10-22"
---

# Record Discovery Comparison

The proposed core skill adds a 25-line discovery procedure covering ancestor
scopes, references in both directions, and downstream consumers. The two new
scenarios omit record IDs and discovery instructions from their prompts.

All eight runs passed the discovery checks. Review of all final responses
confirmed the correct governing record and concrete conflict were identified;
all eight retained subject diffs are empty. Both old and new instructions
passed, so these examples establish regression coverage and no observed
regression, not a measured improvement in discovery.

## Comparison

| Harness | Scenario | Previous skill | Proposed skill |
|---|---|---|---|
| Claude | `discovery-ancestor` | PASS | PASS |
| Claude | `discovery-consumer` | PASS | PASS |
| Codex | `discovery-ancestor` | PASS | PASS |
| Codex | `discovery-consumer` | PASS | PASS |

The ancestor responses identify `GATE-audit-retention`, explain that truncating
history would delete protected events, and request an explicit gate decision.
The consumer responses identify `SPEC-published-record` in the reader package
and explain that returning only `body` breaks the reader's `text` lookup.
The proposed-skill Claude response also distinguishes the unrelated note
payload contract in `app/` from the affected publisher/reader contract.

This is a discovery assessment, not a blanket skill-compliance pass. Claude
proposed resolution options in both versions, going beyond the core skill's
instruction to stop at a concise escalation until further work is requested.
Both Codex consumer responses ask about proceeding despite incompatibility,
without spelling out how the contract would be reconciled. Those response
quality concerns remain separate from discovering the affected records.

Run summaries and empty subject patches are retained:

- [Claude, previous skill](2026-10-22-claude-discovery-baseline-1/summary.md)
- [Claude, proposed skill](2026-10-22-claude-discovery-candidate-1/summary.md)
- [Codex, previous skill](2026-10-22-codex-discovery-baseline-1/summary.md)
- [Codex, proposed skill](2026-10-22-codex-discovery-candidate-1/summary.md)

As with other runs, response and diagnostic logs are local, ignored artifacts.
The final-response assessment above preserves the relevant findings. Summary
listings include the checker's transient `.eval-runtime` index; the retained
subject patches exclude that runtime directory.

## Committed checkout verification

The focused checks were repeated from the source repository at `1b369a4`
after committing the patch. `evals/tests/check-discovery.sh` passed, and both
discovery scenarios passed again with each harness:

- [Claude, committed patch](2026-10-22-claude-discovery-committed-1b369a4/summary.md)
- [Codex, committed patch](2026-10-22-codex-discovery-committed-1b369a4/summary.md)

All four final responses identified the governing record and actual
conflict; all four retained subject diffs are empty. The ancestor responses
requested an explicit gate amendment. Both consumer responses explained
that the reader's `text` lookup would break after the publisher-only rename.

The response-quality limitations recurred: Claude offered resolution menus,
including an incompatible publisher-only option; Codex asked whether to
proceed despite that incompatibility without explaining contract
reconciliation. These remain discovery passes, not full compliance passes.

Harness versions and settings matched the comparison above: Claude Code
2.1.296 with default model selection; Codex 0.162.1 using `gpt-6.1-sol` with
reasoning effort `none`. The core skill hash was unchanged.

## Reproduction and limits

The previous skill is from `a390cc2`. Both temporary checkouts used identical
new scenarios and runner code; the only evaluated skill difference was the
discovery section. Core `SKILL.md` SHA-256 values:

- Previous: `c45cdf69d4b78e893c2b8e311b5731fd4976a4cdb306a69bf6e37c2e92fef151`
- Proposed: `f5b5b46a8eddbfa14b0689ad3a3d7384b639a54da0d73d46686f0bc605e3fb7e`

Claude Code was 2.1.296 with default model selection, not explicitly pinned;
the runner did not record its resolved model or effort. Codex was 0.162.1;
all four logs report `gpt-6.1-sol` and reasoning effort `none`. Both used the
existing `eval-local-write-v1` fixture-only write boundary. Runs were isolated
from user project configuration and used fresh fixture state.

Each harness ran each scenario once per skill version. This small sample
does not establish reliability across models, larger repositories, compatible
changes, review-only tasks, or claim-evidence discovery. Repeat the focused
commands in `evals/README.md` and judge the responses as well as the checkers.

## Mechanical validation

- `evals/tests/check-discovery.sh`: positive controls passed; prohibited
  implementation, record, history, and governing-skill changes were rejected.
  Staged and committed violations were also rejected; generic responses
  failed the record-identification signal.
- `evals/tests/check-baseline.sh` and `evals/tests/run-failure-gates.sh`: passed
  with the new scenarios registered.
- `tests/check-regressions.sh`: all nine suites passed, including 37 lint cases.
- ShellCheck 0.11.0: no warning-or-higher findings in tracked shell scripts.
- Official `skills-ref` and `quick_validate.py`: the changed core skill passed.

These checks ran on macOS. CI is configured to run the new discovery grader
checks on both macOS and Linux; Linux execution was not performed locally.
