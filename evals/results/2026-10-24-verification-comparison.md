---
summary: "Records verification and repair evals, the evidence-loading correction, and the limits of the observed behavior."
read_when:
  - Assessing fresh verification or counterexample repair instructions
  - Repeating verification workflow evals after skill or harness changes
title: "Verification Workflow Comparison — 2026-10-24"
---

# Verification Workflow Comparison

The claims skill now separates independent assessment from historical
reconciliation, distinguishes authors from assigned verifiers, explicitly
attacks composition sufficiency, and follows counterexamples through repair.
The core skill requires loading the claims instructions separately from
verification evidence. Both skills remain project- and technology-agnostic.

Seven scenarios use self-contained Python cache examples. They exercise a
misleading prior pass and unresolved witness, valid independent verification,
an unavailable independent reviewer, compatible component conclusions with a
missing connection, partial and complete repairs, and an unavailable replay
driver. The ordinary runner grades artifact boundaries and outcomes; those
checks alone do not establish independence, reading order, or argument quality.

## Findings

All fourteen baseline and fourteen initial-candidate runs passed the artifact
checks. Both versions already handled composition and the three counterexample
cases correctly. These are regression examples, not evidence of an improvement
in detecting those failures. Both versions also kept an author without an
independent reviewer provisional.

Manual review found failures hidden by the artifact passes:

- Initial Claude reviews read history before assessing the current argument.
  The valid-case review then recorded a pass despite that exposure, treating
  an empty provisional report as an exception the skill did not allow.
- Initial Codex derived the current counterexamples before reading history,
  but its attempt to save the fresh assessment outside the writable fixture
  failed; the same shell command still opened the historical report. The
  valid-case receipt also asserted fresh findings had been recorded without
  an observable pre-history assessment note.
- Baseline Codex tried another reviewer despite already being assigned
  independent verification. Startup failed with an agent-context error.
  Candidate reviews could complete in the assigned role without that attempt.

The second draft made successful recording a completion condition, allowed
conversation notes, and explicitly excluded historical reports from bulk
reads. Codex then emitted its fresh findings before opening history in both
focused cases. Claude continued reading history early. A third draft added
an early verification pointer in the claims skill; this alone did not stop
Claude's early reads. Its falsification reports described a separate fresh
assessor, but the text logs did not independently establish that handoff.

A diagnostic trace exposed the discovery problem: Claude fetched the claims
skill and every file in the evidence directory in one tool call. Its tool
result therefore included the old report before it could act on the newly
loaded instructions. The final correction belongs in the core skill: load
the claims instructions separately before fetching verification evidence.

With that correction, the final Claude trace shows separate skill loading,
current claim/proof/code reads, and witness checks before historical reports.
The valid case completed with a pass; the false case preserved the historical
LOW witness and identified the HIGH violation. Codex's final traces show
explicit fresh findings in conversation before history, followed by
reconciliation and the supported verdict. This is bounded evidence from one
final run per harness/scenario, not a reliability estimate.

Claude's pre-history record was less explicit than Codex's: the trace shows
the checks and a statement that findings were recorded, while its detailed
argument appears in the later receipt. Its final prose sometimes also offers
unrequested choices to narrow a claim. Those limitations are not repaired by
an artifact PASS and remain visible in the retained responses and patches.

## Fixture and trace corrections

The initial composition fixture's imported pass receipts were too thin:
Claude correctly noted their missing coverage and attack details. The final
fixture supplies synthetic component reviews with exact source hashes,
scope, and attacks. Both baselines were rerun against these same corrected
inputs; both still identify the missing connection and reproduce the false
parent while preserving its imports. This fixture correction is not a skill
improvement. Earlier composition patches belong to the earlier fixture.

The diagnostic and final Claude runs used a temporary adapter that changed
CLI serialization from text to verbose streaming JSON, extracted the final
response, and retained tool calls and intermediate statements in the ignored
diagnostic log. The portable version is [trace-claude.py](../trace-claude.py).
Its extraction, exit-status forwarding, empty-response behavior, and version
passthrough were tested with a fake CLI. The prompt, authentication setup,
fixture-only containment, and model selection were unchanged. Logging mode
did change, so the traced runs are not a strict single-variable comparison.
The trace does not establish the internal execution of nested reviewers.

## Retained runs

- Baseline, seven cases each:
  [Claude](2026-10-24-claude-verification-baseline-1/summary.md),
  [Codex](2026-10-24-codex-verification-baseline-1/summary.md).
- Initial draft, seven cases each:
  [Claude](2026-10-24-claude-verification-candidate-1/summary.md),
  [Codex](2026-10-24-codex-verification-candidate-1/summary.md).
- Recording/exclusion correction, two cases each:
  [Claude](2026-10-24-claude-verification-candidate-2/summary.md),
  [Codex](2026-10-24-codex-verification-candidate-2/summary.md).
- Early claims-skill pointer and corrected composition fixture, three cases each:
  [Claude](2026-10-24-claude-verification-candidate-3/summary.md),
  [Codex](2026-10-24-codex-verification-candidate-3/summary.md).
- Corrected composition baseline:
  [Claude](2026-10-24-claude-verification-baseline-2/summary.md),
  [Codex](2026-10-24-codex-verification-baseline-2/summary.md).
- Diagnostic trace:
  [Claude valid verification](2026-10-24-claude-verification-trace-1/summary.md).
- Final core-loading correction, three cases each:
  [Claude, traced](2026-10-24-claude-verification-candidate-4/summary.md),
  [Codex](2026-10-24-codex-verification-candidate-4/summary.md).

All 47 completed sessions passed artifact checks.
Summaries and subject patches preserve every run, including earlier workflow
failures. Responses and diagnostics remain local ignored artifacts; the
findings above retain the material observations. Runner PASS denotes artifact
checks throughout, including when the review sequence failed.

## Reproduction and limits

Baseline skills came from `84b1afa`. Temporary committed checkouts supplied
the skills to fresh fixtures; scenario inputs stayed identical across variants
apart from the explicitly repeated composition correction. Follow the
[eval instructions](../README.md#validating-verification-and-counterexample-handling).

Final distributed skill SHA-256 values:

| Skill | SHA-256 |
|---|---|
| `assurance-records` | `157d2e4d513c5842c864ceebc238d2909bf029455f3d6e2c8d4310cd12b4e8e1` |
| `assurance-records-claims` | `c5771c62231d88cebf02c58efe3fc0850dcff3d38a461ed4796ec19a51db79d6` |

Claude Code was 2.1.296 with default model selection; generated model names
are not authoritative runtime metadata. Codex was 0.162.1; diagnostics report
`gpt-6.1-sol` with reasoning effort `none`. The existing `eval-local-write-v1`
boundary and escape probes remained in place for every live run.

These examples validate small supplied arguments and witnesses. They do not
establish production correctness, full author-to-reviewer orchestration,
behavior across arbitrary repositories, or a general probability of following
the instructions. The composition witnesses exercise sequential interruption
and retry, not real database crashes or distributed concurrency.

## Mechanical validation

- All nine contract suites passed, including 37 lint cases.
- The new grader suite executed actual witnesses before and after repairs,
  rejected wrong verdicts and unintended repair behavior, and rejected changes
  to protected claims, witnesses, and skills, including staged/committed edits.
- Runner failure gates passed with all 32 scenarios; immutable-baseline checks
  passed after registering the new shared checker and controls.
- Existing formal/composition/residual grader checks passed with pinned Z3
  5.3.1, including real symbolic obligations and negative controls.
- Official `skills-ref`, skill-creator validation, ShellCheck 0.11.0, Python
  compilation, YAML/frontmatter, local report links, and whitespace checks
  were run on the final artifacts.

The first baseline-suite attempt missed registration of the new scenarios;
that was corrected. Its next real containment probe hit the outer sandbox's
nested-sandbox restriction; the elevated launcher passed with the inner
fixture boundary retained. The contract test itself passed on its first run,
although the surrounding reporting command used a read-only zsh variable;
the final contract run completed cleanly. The system Python was too old for
`skills-ref`; pinned tools ran from a temporary Python 3.13 environment.

Checks ran locally on macOS. CI includes the new grader and trace-adapter
checks on macOS/Linux; remote CI and Linux execution were not run here.
