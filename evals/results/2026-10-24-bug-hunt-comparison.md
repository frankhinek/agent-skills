---
summary: "Records bug-hunt packaging checks, baseline comparisons, a corrected fixture, and remaining behavioral limits."
read_when:
  - Deciding whether to use or refine assurance-records-bug-hunt
  - Reviewing bug-hunt evaluation evidence and grader limits
title: "Bug-Hunt Implementation Evaluation"
---

# Bug-Hunt Implementation Evaluation

Date: 2026-10-24. The fourth skill is ready for a bounded real-project trial.
It remains project-agnostic, explicitly commissioned, and findings-first.
No claim tree, new verification framework, or project-specific dependency was
introduced. These fixtures support trial use, not a claim of improved production
bug discovery or complete instruction compliance.

## Change and validation

The [skill](../../skills/assurance-records-bug-hunt/SKILL.md) adapts Manmeet's
harm-driven discovery and pstack's executable-evidence practices. Existing
core/claims rules retain authority over records, evidence, verification,
staleness, and residual acceptance. The
[adaptation brief](../../docs/bug-hunt-adaptation.md) retains the source rationale.

Installation, vendoring, bootstrap guidance, documentation, and CI now include
four skills. Copy transaction version 2 covers four entries; recovery of version
1 still owns exactly the original three. Upgrade checks preserve local edits,
new-path collisions, and entries an old interrupted transaction never owned.
The pstack MIT notice travels with the distributed skill.

Executed on macOS:

- All **10 packaging/contract regression suites**, including 37 linter cases,
  installer outcomes, three-to-four-skill upgrades, payload identity, local-edit
  preservation, interrupted upgrades, legacy recovery, and malformed metadata.
- Hunt grader controls: real defect/repaired executions, always-pass/always-fail
  witnesses, absent/empty/symlink artifacts, unauthorized product/record changes,
  and staged/committed mutations. An optional dangling witness link is rejected.
- Shared immutable-baseline checks and runner failure gates across all 38
  registered scenarios. These suites use synthetic adapters, not live agents.
- Existing verification/counterexample grader regression and fixture-builder
  regression.
- ShellCheck 0.11.0 at warning severity across tracked shell scripts;
  official `skills-ref` validation of all four skills; whitespace checks.

The shared-baseline suite initially failed at its nested sandbox startup inside
the parent sandbox. It passed when rerun with the outer command authorized;
the eval's own fixture-write boundary remained active. Linux CI is configured
but was not executed in this local run.

## Comparison design

Baseline skills: source commit `9308aa7`, `skills/` tree
`5c9ac1c64f44651729b876ac96df16fdfbf4c474`.
Candidate skills: `skills/` tree
`bf23cf2d6586bf9827adab4c331a051fe1715f68`.
The candidate skill text remained unchanged throughout the comparison.

Each pack received the same six natural tasks: recovery loss, retry duplication,
a clean bounded surface, an unavailable dependency, a preserved known
falsification, and an ordinary label edit. Prompts did not name the new skill.
Both used the same fixture sandbox and retained product/record protections.

Harnesses: Claude Code 2.1.296 and Codex CLI 0.162.1. Codex reported
`gpt-6.1-sol`; the Claude trace adapter did not retain its resolved model ID.
Claude used the same trace adapter in both arms. CLI defaults were not overridden.
Single samples cannot establish model-independent improvement or reliability.

There were **32 live sessions**: 24 initial sessions and eight reruns of the
two affected scenarios after correcting the fixture/control described below.
Final comparison uses rerun recovery/clean cases and the original four remaining
cases: 12 observations per pack. Earlier results remain available.

| Pack | Harness | Final mechanical result |
|---|---|---|
| Baseline | Claude | 6/6 |
| Candidate | Claude | 6/6 |
| Baseline | Codex | 6/6 |
| Candidate | Codex | 6/6 |

These counts cover artifact boundaries, task engagement, and required witness
controls. They are not scores for reasoning quality, instruction order, complete
coverage, or bug-finding effectiveness.

## Fixture correction

The initial clean queue requeued `running` jobs only on startup. It still lost
progress after an output transaction failed and the same worker retried. The
recovery grader's repaired counterpart had the same omission.

Both baseline agents found this defect in the purported clean case. Candidate
Codex included the failure path in its recovery witness, which correctly failed
against the incomplete repaired counterpart. Those three initial mechanical
failures are test-design failures, not evidence of worse agent behavior.
The candidate clean runs stayed within restart coverage and disclosed the
same-process retry gap; their passing results did not establish a clean fixture.

The corrected clean implementation and grader counterpart also select abandoned
`running` rows on subsequent work calls, under the supplied single-worker
contract. The synthetic witness now checks a one-time SQLite output failure
followed by same-process retry. It explicitly identifies its temporary trigger
as a rollback/control-flow test, not a physical disk fault. Recovery and clean
were rerun in both harnesses and both arms; the skill instructions were not tuned
in response to these runs.

## Review beyond the scores

Reports, diffs, responses, and available tool traces were reviewed. Required
witnesses execute against actual product entry points and distinguish the
injected defect from the checker-owned repair. Corrected clean reports describe
their tested scope; neither candidate creates claims or asserts an independent
claim pass. Missing-driver cases retain conditional concerns and name the
unavailable evidence. Routine edits change only the requested label and do not
start a hunt.

Two baseline reasoning problems were hidden by mechanical passes:

1. **Claude retry report:** it says interruption after receipt insertion rolls
   back both inserts. The earlier explicit item commit makes that false; only
   the receipt rolls back. Its main duplicate-effect witness is valid, but the
   report incorrectly labels this additional boundary safe. The candidate
   report correctly describes the same duplicate mechanism.
2. **Codex authority report:** it promotes conflicting payload resubmission to
   a confirmed acceptance defect and asserts that it must return rejection.
   The contract supplies one payload per ID, not a rejection-response rule.
   This needs requirements clarification. Both candidate reports retain that
   distinction rather than inventing an oracle.

For the authority case, all four saved new witnesses were additionally replayed
against original and fully repaired copies. Candidate Claude/Codex and baseline
Claude fail on the original and pass after recovery/retry repair. Baseline Codex
still fails its conflicting-payload assertions after its valid output-retry case
passes. That supports the oracle concern above; it does not imply the repair
satisfies an unrequested rejection rule.

The candidate has a remaining procedural miss: **Claude authority read
`tests/known_loss.py` before loading the claims skill.** Its trace then says
“before evidence reads” and loads that skill before `proof.md` and
`verification.md`. The known witness is already evidence, so the new skill's
literal load-before-evidence instruction was not fully followed. No evidence
was changed or independent pass claimed; this was a history-informed hunt.
Codex loaded claims first. Artifact checks cannot establish this ordering.

Candidate reports generally made assumptions, execution limits, and stopping
boundaries more explicit. This is an observation from a small comparison, not
a causal improvement estimate. Report length also grew in some cases; a real
trial should assess whether that extra detail earns its cost.

## Retained evidence

Initial runs (including the superseded fixture/control outcomes):

- [Baseline Claude](2026-10-24-claude-hunt-baseline/summary.md)
- [Candidate Claude](2026-10-24-claude-hunt-candidate/summary.md)
- [Baseline Codex](2026-10-24-codex-hunt-baseline/summary.md)
- [Candidate Codex](2026-10-24-codex-hunt-candidate/summary.md)

Corrected recovery/clean reruns:

- [Baseline Claude](2026-10-24-claude-hunt-baseline-corrected/summary.md)
- [Candidate Claude](2026-10-24-claude-hunt-candidate-corrected/summary.md)
- [Baseline Codex](2026-10-24-codex-hunt-baseline-corrected/summary.md)
- [Candidate Codex](2026-10-24-codex-hunt-candidate-corrected/summary.md)

Each directory retains summaries and agent-produced diffs. Raw responses/tool
traces remain local and ignored; the ordering observation above is preserved
here because artifact diffs cannot show it.

## Next use and limits

Trial one real implementation surface with named harms and a stopping boundary.
Assess actionable findings, reproduction quality, missed coverage, report cost,
and time spent. Refine from that use rather than adding more workflow now.

These small fixtures do not measure unknown-defect discovery in a large system,
arbitrary concurrency, real power-loss behavior, adversarial peers, formal-tool
integration, or independent claim verification. Passing tests do not remove
judgment or execution cost. The remaining sequencing miss also means the skill
should not be treated as enforced procedure merely because artifacts pass.
