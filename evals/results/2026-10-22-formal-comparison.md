---
summary: "Records formal-evidence and claim-composition comparisons, fixture repairs, and validation limits."
read_when:
  - Assessing formal evidence or transitive staleness instructions
  - Repeating formal and composition evals after skill or model changes
title: "Formal Evidence Comparison — 2026-10-22"
---

# Formal Evidence Comparison

The proposed skills add deductive `formal` evidence, explicit composition
rules, and transitive loss of support. Executable verification owns the
properties it checks; claims retain material connections and assumptions
outside that coverage. Formal tool dependency graphs are not duplicated in
claim records.

The final comparison has ten candidate passes across five scenarios and two
harnesses. Baseline runs passed seven of the ten. Reviewing the retained
patches and final responses confirmed the scenario-specific findings below.
These are focused behavior checks, not blanket proof-quality judgments.

## Comparison

| Scenario | Claude baseline | Claude proposed | Codex baseline | Codex proposed |
|---|---|---|---|---|
| `formal-local` | PASS | PASS | PASS | PASS |
| `formal-proof` | FAIL: `search` label | PASS | FAIL: `search` label | PASS |
| `formal-mismatch` | PASS | PASS | FAIL: `falsified` verdict | PASS |
| `formal-staleness` | PASS | PASS | PASS | PASS |
| `claim-composition` | PASS | PASS | PASS | PASS |

The first three rows use round 2, after fixture/grader corrections. The last
two use round 1; those fixtures and their grading were unchanged. Both
versions ran with the same scenario inputs and harness settings within each
comparison. Skill content stayed fixed throughout both rounds.

- **Local property:** neither version created a redundant claim. Claude left
  the tree unchanged; Codex documented the theorem with SMT comments while
  preserving executable tokens.
- **Formal argument:** both baseline agents called an unbounded symbolic
  result `search`. Both proposed runs used `formal`, identified the exact
  obligation, revision, Z3 version, command, and `unsat`, and distinguished
  the model result from the Python/JSON connection established by reading.
  All four preserved source, the claim, and executable verification, and
  created no independent verdict. The label difference is a classification
  improvement; both baseline arguments already explained unbounded scope
  and the production connection.
- **Insufficient theorem:** all four identified missing upper-bound evidence
  and missing model/exporter correspondence. Baseline Codex recorded
  `falsified` while explicitly acknowledging no implementation counterexample;
  the proposed run correctly used `provisional`. Both Claude runs also used
  `provisional`. No run rewrote the supplied claim or argument.
- **Transitive staleness:** all four traced the changed driver premise through
  `CLAIM-reservation`, `CLAIM-single-post`, and `CLAIM-retry-safe`, made all
  three verdicts provisional, and named restoration work. Unchanged model
  evidence was not extended to the unassessed driver. The unrelated pass and
  existing falsification survived. No claim statement changed.
- **Composition:** all four rejected the attempted combination of single-worker
  and multi-worker premises in one deployment, left the parent provisional,
  and preserved the conditional imports. These two passing-baseline scenarios
  provide regression coverage, not observed improvement from the new wording.

## Retained runs and fixture corrections

Round 2 provides the final comparison for local ownership, formal arguments,
and insufficient evidence:

- [Claude baseline, round 2](2026-10-22-claude-formal-baseline-2/summary.md)
- [Claude proposed, round 2](2026-10-22-claude-formal-candidate-2/summary.md)
- [Codex baseline, round 2](2026-10-22-codex-formal-baseline-2/summary.md)
- [Codex proposed, round 2](2026-10-22-codex-formal-candidate-2/summary.md)

Round 1 retains all five scenarios, including the final staleness/composition
results and superseded exploratory results for the first three:

- [Claude baseline, round 1](2026-10-22-claude-formal-baseline-1/summary.md)
- [Claude proposed, round 1](2026-10-22-claude-formal-candidate-1/summary.md)
- [Codex baseline, round 1](2026-10-22-codex-formal-baseline-1/summary.md)
- [Codex proposed, round 1](2026-10-22-codex-formal-candidate-1/summary.md)

All 32 raw run results and their patches are retained without changing failed
summaries into passes. Round 1 exposed three problems in the eval:

1. The local-property grader rejected harmless SMT comments. It now compares
   executable tokens with the immutable baseline, allowing comments.
2. Python imports produced bytecode that the protected-tree check treated as
   an unauthorized artifact. Generated `__pycache__/*.pyc` is now excluded;
   source changes still fail.
3. "Python integer" left bool/subclass behavior ambiguous. The claim fixtures
   now specify `type(raw) is int`, conditional normal return, and
   `type(score) is int`. Both skill versions received the same correction.

All affected scenarios were rerun for both versions and harnesses. These
fixture repairs are not skill improvements. A separate synthetic grader test
also caught an overly broad `formal` text signal; it now requires a label and
rejects the deliberately mislabeled `search` control.

As in existing evals, summaries and subject patches are durable; final-response
and diagnostic logs remain local ignored artifacts. This report preserves
the relevant semantic review. Round-1 patches belong to the original fixtures,
so do not apply them to the corrected fixtures as if their baseline were identical.

## Reproduction and limits

Baseline skills are from source commit `a1fd359`. Temporary committed
checkouts supplied identical eval infrastructure, with only the three skills
different. SHA-256 values identify the evaluated instructions:

| Skill | Baseline | Proposed |
|---|---|---|
| `assurance-records` | `f5b5b46a8eddbfa14b0689ad3a3d7384b639a54da0d73d46686f0bc605e3fb7e` | `b4699371694beac6eb635039de77abf20dcfc839ed46f9ffc4e5ebcf5fa7dd84` |
| `assurance-records-claims` | `801b7c6ce0d40ad7d4b9c8ff37514eafb808b70ee4f426d64fb28ac708bc7791` | `60b7ed8817d4f760bf6ec30c1b3e92bbb30590d93cfd01fb7f9bb4fa92479685` |
| `assurance-records-upkeep` | `03932b54e53f78ba93777e340c386c836c07a735aa86c941334de5af456958b7` | `fb4cb6836474a2da1f9b59cd170dbff6f597920f7cdf93493ddc3ac39379e789` |

Claude Code was 2.1.296 with default model selection; the runner did not
record a resolved model or effort. A model name asserted in generated prose
is not authoritative metadata. Codex was 0.162.1; logs report `gpt-6.1-sol`
with reasoning effort `none`. Both used the existing `eval-local-write-v1`
boundary, isolated user configuration, and fresh fixture state. Z3 came from
`z3-solver==5.3.1.0`, reporting version 5.3.1 and build
`ac9156f97cb44e56472e1c841f7a2beb1e976b24`.

Codex diagnostics expose tool commands/results, including the positive SMT
check. Claude's text-output logs do not provide an equivalent tool trace;
its execution claims are visible in its evidence and final responses, not
independently established by those logs. The actual fixture obligations were
also run directly by the regression suite with the pinned solver.

The composition and mismatch prompts assign the subject as an independent
reviewer of a supplied argument. Codex additionally attempted nested reviewer
startup, which failed because the CLI's agent context was unavailable; the
evidence records that limitation. These runs do not validate nested-agent
verification orchestration or justify an independently verified `pass`.

One final sample per harness/version/scenario cannot establish reliability.
Claude still offered unnecessary follow-up options for the local theorem;
its proposed response suggested application use could justify a claim without
explicitly requiring a remaining material obligation. Proof prose also uses
runtime assumptions that still need review against a real deployment. Passing
the artifact grader does not validate every statement in a derivation.

These examples do not exercise Lean, Verus, TLA+, cyclic imports, checker
timeouts, admitted theorems, or actual production bookkeeping behavior. The
SMT proofs cover small mathematical models; production correspondence remains
a separate reviewed argument. Follow [the eval instructions](../README.md)
to repeat the focused cases and inspect semantics as well as artifact checks.

## Mechanical validation

- `tests/check-regressions.sh`: all nine suites passed, including 37 lint cases.
- `evals/tests/run-failure-gates.sh`: passed, including all 24 registered
  scenarios with fake harness adapters.
- `evals/tests/check-baseline.sh`: passed immutable-baseline checks.
- `evals/tests/check-formal-semantics.sh`: all real SMT obligations returned
  `unsat`; a broken clamp returned `sat`. Synthetic controls exercised allowed
  comments/bytecode, prohibited theorem/source/skill changes, wrong evidence
  labels/verdicts, every dependency level, and preservation of unrelated and
  falsified evidence. Staged and committed source violations were rejected.
- ShellCheck 0.11.0, Python compilation, YAML checks, and source/documentation
  whitespace checks passed. Retained unified patches preserve their required
  blank context lines and are excluded from prose whitespace checking.
  Official `skills-ref` and `quick_validate.py` accepted all three changed skills.

Checks ran on macOS. CI is configured for macOS and Linux; Linux execution and
remote CI were not performed during this local change.
