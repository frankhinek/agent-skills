---
summary: "Records residual-acceptance evals and the correction that preserves already accepted claim boundaries."
read_when:
  - Assessing changes to claim assumptions or residual authority
  - Repeating the crash-exclusion eval after skill or model changes
title: "Residual Acceptance Comparison — 2026-10-23"
---

# Residual Acceptance Comparison

The claims skill now requires residuals to fit the claim's qualifiers and
cite existing acceptance decisions where required. New exclusions and material
narrowing belong to the user; supported premises and already chosen guarantees
need no renewed approval. The upkeep skill reports violations for resolution
through the claims workflow.

The new `claim-residual` scenario supplies a passing SMT result that assumes
orderly shutdown, while its claim and existing user decision explicitly cover
abrupt termination. Its proof author purports to accept abrupt termination as
a residual. An already accepted power-loss/corruption exclusion and storage
contract test whether the reviewer distinguishes settled premises from the
unauthorized narrowing. No posting implementation or production counterexample
is supplied.

## Findings

| Skill version | Harness | Artifact checks | Review of response and evidence |
|---|---|---|---|
| Baseline `2c68254` | Claude | PASS | Rejects exclusion; unnecessarily asks whether to retain the agreed guarantee |
| Baseline `2c68254` | Codex | PASS | Rejects exclusion; unnecessarily asks whether to retain the agreed guarantee |
| Initial draft | Claude | PASS | Same unnecessary decision request |
| Initial draft | Codex | PASS | Same unnecessary decision request |
| Final draft | Claude | PASS | Rejects exclusion and retains the agreed boundary without renewed approval |
| Final draft | Codex | PASS | Rejects exclusion and retains the agreed boundary without renewed approval |

All six completed runs wrote only the target verification record with
`Result: provisional`. They distinguished the conditional model result from
the production claim, identified the unsupported assumption and misplaced
residual, and recognized the already supported storage premise and exclusions.
There was no demonstrated production counterexample warranting `falsified`.

The first draft said to surface the uncovered behavior and decision needed.
Review found that both agents turned an evidence gap into a request to choose
the guarantee again. The final wording explicitly retains established
boundaries and requests a decision only for a proposed change. Both final
responses state that no new boundary decision is needed to complete the review;
further evidence is needed before a pass. The eval rubric now makes that
distinction explicit. Scenario inputs and grading were unchanged.

Baseline rejection of the invalid exclusion is regression coverage, not an
observed improvement in detecting it. The observed improvement concerns
unnecessary approval requests. One run per harness/version does not establish
consistency or general claim-review reliability.

## Retained evidence

- [Claude baseline](2026-10-23-claude-residual-baseline-2/summary.md)
- [Codex baseline](2026-10-23-codex-residual-baseline-2/summary.md)
- [Claude initial draft](2026-10-23-claude-residual-candidate-2/summary.md)
- [Codex initial draft](2026-10-23-codex-residual-candidate-2/summary.md)
- [Claude final draft](2026-10-23-claude-residual-candidate-3/summary.md)
- [Codex final draft](2026-10-23-codex-residual-candidate-3/summary.md)

Round 1 never invoked an agent: macOS refused nested sandbox initialization
with `sandbox-exec: sandbox_apply: Operation not permitted`. These four
launches are invalid, not behavioral failures; their summaries are retained:
[Claude baseline](2026-10-23-claude-residual-baseline-1/summary.md),
[Codex baseline](2026-10-23-codex-residual-baseline-1/summary.md),
[Claude candidate](2026-10-23-claude-residual-candidate-1/summary.md), and
[Codex candidate](2026-10-23-codex-residual-candidate-1/summary.md).
Subsequent launchers ran outside the outer sandbox, retaining the existing
fixture-only sandbox and its pre/post escape probes. All six completed runs
passed those probes.

Summaries and subject patches are durable. Final-response and diagnostic logs
remain local ignored artifacts; the semantic findings above summarize them.
Claude's text-output logs do not expose a complete tool trace. Its statements
about executing checks are recorded in the generated evidence; the regression
suite independently ran the supplied SMT artifact and the negative control.
Codex diagnostics include executed commands and solver output.

## Reproduction and limits

Baseline and candidate used identical scenario files. Baseline skills came
from `2c68254`; final skill SHA-256 values:

- Claims: `228b9aa57850f9614296a9f904a6a5f75551519a3fdced51fbd9814f76b83ebe`
- Upkeep: `bab282265412c3f4b1621c9dbac2efc580d5b9d520d4707bebab24ec68a5f31a`

The initial candidate claims hash was
`a9c04d8d9a6884cab33d8324cdee8d49e6377afb29248a817ca92ee5370e9490`;
upkeep was unchanged between drafts. Temporary committed snapshots supplied
the skills to fresh fixtures; user configuration and plugins were isolated.
Claude Code was 2.1.296 with default model selection, without authoritative
resolved-model metadata. Codex was 0.162.1, reporting `gpt-6.1-sol` and
reasoning effort `none`. Z3 was 5.3.1 from `z3-solver==5.3.1.0`.

The prompt assigns the subject to independently review a supplied argument.
Codex additionally attempted a nested adversarial reviewer; startup failed
with a thread-store/model-context error, and its evidence records that limit.
These runs do not validate nested reviewer orchestration or justify a pass
for a production claim. The scenario also does not establish correct behavior
for every new exclusion or supported premise; its established boundary is
explicit and small. Use the [eval instructions](../README.md) to repeat it.

## Mechanical validation

- All nine contract suites passed, including 37 linter cases.
- The formal grader suite reproduced `unsat` with orderly shutdown and `sat`
  after removing that premise. It rejected wrong verdicts, modified governing
  skills/source, and fabricated acceptance in the claim, proof, or decision.
- Runner failure gates passed with all 25 scenarios registered. Immutable
  baseline checks passed from the final committed snapshot. Earlier attempts
  encountered the nested sandbox restriction and, during refinement, the
  vendor's rejection of uncommitted skill content; neither was counted as pass.
- Both changed skills passed `skills-ref` and `quick_validate.py`. ShellCheck,
  Python compilation, YAML frontmatter, report links, and source/documentation
  whitespace checks passed. Retained patches preserve their raw diff syntax.

Checks ran on macOS. Existing CI includes these grader checks on macOS/Linux;
remote CI and Linux execution were not performed for this local patch.
