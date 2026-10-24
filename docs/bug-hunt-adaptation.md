---
summary: "Records the bug-hunt adaptation, authority boundaries, upstream rationale, and validation criteria."
read_when:
  - Adding a harm-driven bug-hunt workflow to assurance-records
  - Reviewing the bug-hunt workflow's scope or validation
title: "Bug-Hunt Adaptation Brief"
---

# Bug-Hunt Adaptation Brief

Assessment date: 2026-10-24. Local baseline: `cc1a902`.
Implementation date: 2026-10-24; source baseline: `9308aa7`.
Status: implemented as [assurance-records-bug-hunt](../skills/assurance-records-bug-hunt/SKILL.md),
with packaging and focused evaluations. Real-project usefulness remains to be tested.
See the [implementation evaluation](../evals/results/2026-10-24-bug-hunt-comparison.md)
for results, the corrected test fixture, and remaining workflow limitations.

## Recommendation

Trial the small, explicitly invoked `assurance-records-bug-hunt` skill on one real surface.
Use it to investigate a bounded surface for named harms, with findings and
reproducers as the default output. Keep the instructions project- and
technology-agnostic. Validate its boundaries on small executable fixtures,
then use it on one real implementation before expanding the workflow.

The current [claims skill](../skills/assurance-records-claims/SKILL.md)
already owns evidence, composition, independent verification, residuals,
staleness, and counterexample repair. The new capability chooses what
to challenge, including behavior with no existing claim. It refers to
those rules rather than duplicate or redefine them.

Earlier deferral concerned premature claim-tree construction and a broad
proof campaign. The current rules now supply the needed authority and
evidence boundaries. That supports drafting and testing a narrow workflow
before a production implementation exists. Its usefulness on real projects
remains untested; preserving context alone would not establish that usefulness.

## Upstream grounding

Reviewed Manmeet's
[agentic-claims-bug-hunt](https://github.com/maan2003/public-skills/blob/db24f78afc132ef60c92a06c1ffcfb441fdc92fa/skills/agentic-claims-bug-hunt/SKILL.md)
at `db24f78afc132ef60c92a06c1ffcfb441fdc92fa`, the public repository HEAD
observed on the assessment date. Its instruction material falls under the
repository's [CC0 dedication](https://github.com/maan2003/public-skills/blob/db24f78afc132ef60c92a06c1ffcfb441fdc92fa/LICENSE.md).

Upstream starts from named harms under honest counterparties and an adverse
environment. It uses a feature-by-harm root table, commissioned leaf claims,
counterexamples, and plain-language companion bug summaries. These are source
observations; the narrower workflow below is the local adaptation.

## Retain and adapt

- Start from consequences: lost or corrupted durable state, duplicate effects,
  permanently stuck operations, false success reports, and abandoned accepted
  work. Include value loss or cross-owner effects when the target has them.
  Derive additional harms from governing requirements; this list is not exhaustive.
- Identify relevant operations from code and interfaces. Include background
  tasks, startup, replay, cancellation, and recovery; public entry points alone
  miss obligations that outlive their callers.
- Use a small operation-by-harm table as investigation notes. State coverage
  gaps and how the operation inventory was obtained. It is not a root CLAIM,
  an exhaustive assurance certificate, or a mandatory permanent index.
- Inspect interruption points, overlapping operations, transient I/O failure,
  independent worker failure, and restart. Separate persisted facts from memory,
  and identify who retries or reconstructs each accepted obligation.
- Examine delayed guards, reported success without observed completion,
  optimistic status answers, replacement ordering, and shared-resource ownership.
- Prefer executable witnesses and regression tests. Preserve the revision,
  triggering conditions, schedule, expected behavior, and observed result.
  Distinguish a demonstrated implementation defect from a model-only example,
  a code-reading concern, and an unresolved requirements question.

## Boundaries that must survive adaptation

1. **Explicit activation and bounded effort.** A requested hunt names a surface
   and meaningful harms. Ordinary implementation, lint, or skill discovery must
   not start a repository-wide hunt. Set a stopping scope or budget; report
   unexamined work rather than recursively commissioning every uncovered cell.
2. **No automatic records.** A hunt alone does not authorize creating, narrowing,
   retiring, or deleting CLAIM or GATE records. Propose qualifying claims using
   the [core thresholds](../skills/assurance-records/SKILL.md). A test or constraint
   that fully owns a local property may need no claim at all.
3. **Use the project's fault model.** Honest counterparties are a useful starting
   scope, not a security verdict. State durability, clocks, cancellation, retry,
   and deployment assumptions explicitly. Do not import a universally monotonic
   clock assumption or exclude availability/performance when requirements make
   them material. Liveness arguments must name eventual-recovery or scheduling
   assumptions; endless faults do not establish permanent wedging after recovery.
4. **Coverage is not acceptance.** Leaving a behavior unexamined does not accept
   its risk or narrow an existing guarantee. New residual acceptance and changes
   to governing boundaries still follow the claims and core authority rules.
5. **Discovery is not independent verification.** A hunt may use prior bugs to
   guide investigation. It cannot present that history-informed work as the
   fresh assessment required for a claim pass. Route requested verification
   through the claims skill before reading evidence; reconcile historical
   witnesses there after the fresh phase.
6. **No automatic pass.** A clean bounded hunt means no counterexample found
   within the reported coverage. It does not establish absence of bugs. A model
   witness needs a justified connection before it falsifies a production claim.
   Missing tools and unavailable checks remain evidence gaps.
7. **Preserve existing findings.** Cite known bugs instead of rediscovering them
   for credit. Follow the claims workflow for authorized evidence updates to
   affected existing claims. Retain unresolved falsifications and propagate lost
   support according to that workflow; do not mark every dependent claim false.
8. **Respect repair scope.** A hunt produces findings and witnesses. If the user
   also requests fixes, proceed with the authorized repairs and preserve the
   reproduction and before/after evidence. Do not require another permission
   round just because upstream separates discovery and repair changes.
9. **Avoid duplicate reporting systems.** Use the requested report location or
   existing issue/test conventions. No mandatory `found-bugs/` tree, companion
   index, claim per row, security claim tree, or claim record for an empty result.
   Publishing issues or messages still requires authorization.
10. **No bug quota.** Finding a real defect is useful; finding none honestly is
    also valid. Do not inherit an expectation that most claims must be falsified.

Formal checks remain complementary: they can test selected properties or
produce witnesses, while the hunt challenges whether the right properties,
failure paths, and implementation connections were selected. Reuse existing
artifacts; require no particular solver, language, runtime, or proof system.

## Costs and integration points

- **Scope and maintenance:** another skill introduces routing, examples, tests,
  and upkeep. Keep investigation instructions separate from the core convention;
  avoid making routine changes load a fault-analysis checklist.
- **Packaging:** [install.sh](../install.sh) and [vendor.sh](../vendor.sh)
  now enumerate four managed skills. Bootstrap guidance, inventory consumers,
  README, fixture assertions, and CI validation include the new skill.
  Transaction version 2 owns four entries; version-1 recovery retains its
  original three-entry ownership, preserving unrelated additions.
- **Upgrade safety:** exercise refresh from an existing three-skill installation,
  local-edit preservation, payload checks, and interrupted-refresh recovery.
  Retain the [vendoring integrity boundary](../adrs/0001-vendoring-integrity-boundary.md).
  Do not introduce a general plugin registry merely to add one skill.
- **Behavioral uncertainty:** a clear instruction does not establish agent
  behavior. The [verification eval report](../evals/results/2026-10-24-verification-comparison.md)
  found workflow failures hidden by artifact passes. Inspect investigation
  reasoning and observable tool behavior as well as output files.

The material downside is the added workflow and validation cost. There is no
identified conceptual conflict if the authority and evidence boundaries above
hold. Directly adopting upstream's claim-tree machinery would create one.

## Focused validation before real use

Use generic fixtures with a buggy and corrected implementation where relevant:

- Accepted background work is abandoned after a transient error or restart;
  the hunt identifies the durable obligation and produces a valid witness.
- Success is reported before a durable effect, or concurrent/retried operations
  duplicate an effect; the witness preserves the real triggering conditions.
- A corrected implementation survives those checks; the hunt reports bounds
  without inventing a bug, a durable claim, or an independent pass.
- An existing claim and known witness are encountered; the hunt preserves their
  authority and distinguishes discovery from requested independent verification.
- A required tool is unavailable or only design documents exist; the report
  distinguishes untested concerns from demonstrated implementation defects.
- Ordinary implementation or bare skill loading leaves the hunt inactive.

Check unauthorized record/source mutations mechanically where possible.
Review witness validity, harm attribution, fault assumptions, honest negative
results, and stopping behavior manually. Compare the current pack and adapted
pack on identical fixtures; baseline successes establish regression coverage,
not an improvement. Run packaging regressions and skill validation as well.

After those checks, trial one real surface and evaluate actionable findings,
reproduction quality, missed coverage, and effort. Refine from observed use
rather than expanding into a general assurance framework before that trial.

## Pstack comparison

Reviewed `cursor/plugins` at
[`9580c23696ac8d7abed0c166f2f9918800afb819`](https://github.com/cursor/plugins/tree/9580c23696ac8d7abed0c166f2f9918800afb819/pstack).
Inspected the complete pstack skill inventory, the relevant verification and
review instructions, the bug-fix playbook, and Benny's reproduction workflow.
This is a comparison of source instructions; no pstack workflow was executed
and no behavioral comparison against Manmeet's skill was performed.

Recommendation remains Trial. Manmeet supplies the closer foundation for
finding unnamed harms across crash, restart, concurrency, and recovery paths.
Pstack supplies useful procedures for establishing executable evidence. Use
both selectively inside one assurance-records bug-hunt skill; existing claims
rules continue to own authority, evidence classifications, and verdicts.

Relevant pstack skills and their fit:

- [blast-radius](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/skills/blast-radius/SKILL.md)
  investigates a change's effects beyond direct callers and tests the crucial
  safety premises against actual code and pinned dependency behavior. This is
  the closest lightweight change-review workflow. Adapt it when a hunt begins
  from a diff; do not assume every system's safety reduces to one premise.
- [create-formal-verification-skill](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/skills/create-formal-verification-skill/SKILL.md)
  chooses a consequential property, selects a suitable checking tool, relates
  model steps to actual code, and runs the resulting procedure against a
  deliberately broken code variant. It is the strongest source for the hunt's
  executable-check procedure. Its default deliverable is a new project-local
  skill; reuse existing tests and tooling before adding that extra artifact.
- [maintain-formal-verification-skill](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/skills/maintain-formal-verification-skill/SKILL.md)
  supplies a concrete drift investigation: run the old check, inspect changes
  since its last correspondence review, update the implementation model, rerun,
  and distinguish stale modeling from an actual defect. It complements the
  existing claims staleness rules; it does not replace them.
- [interrogate](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/skills/interrogate/SKILL.md)
  conducts a multi-model adversarial review of supplied changes or files.
  Its broader review rubric is useful context, but it supplies less specific
  harm and failure-path discovery than Manmeet. Model agreement is not a
  substitute for a valid witness or independent claim verification.
- [create-verification-skill](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/skills/create-verification-skill/SKILL.md)
  builds an app-driving procedure and a maintained feature map. Borrow real
  entry-point checks, observed side effects, instance isolation, and retention
  of evidence through cleanup. Do not require a new feature-map corpus for
  every hunt.
- [statechart](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/skills/statechart/SKILL.md)
  presents TLA+ results as diagrams and numbered traces, with replay against
  implementation where code exists. It is a potential optional presentation
  tool for model-based findings. Its Node/Java/TLC tooling is not a required
  dependency of a portable hunt; its scripts were not evaluated in this review.
- [Benny's reproduce-and-fix-issues](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/automations/benny/skills/reproduce-and-fix-issues/SKILL.md)
  handles already-reported Slack issues through configured UI control and
  before/after evidence. Its automation, coordination, and UI requirements make
  it a poor foundation for a general proactive hunt.

Specific adaptations worth carrying forward:

1. Identify the premises on which an operation's safety depends, follow their
   downstream effects, and exercise the actual implementation where possible.
2. Validate newly built search harnesses with meaningful broken variants in an
   isolated scratch copy. For a separate model, distinguish a failed model
   mutation test from detection of a real implementation change; the latter
   requires checking or refreshing the model-to-code correspondence. Reuse the
   existing `search` negative-control rule rather than defining another rung.
   A deductive proof's validity does not depend on deliberately breaking it;
   mutation controls test the surrounding checker and correspondence workflow.
3. Replay model counterexamples against reachable implementation behavior;
   preserve uncertainty when only the model or part of the execution was tested.
4. Leave a runnable command and retained witness, with versions, bounds, and
   assumptions. Exercise that command as a future agent would before handing
   it off. Existing project test/model locations remain the default owners.

Compatibility limits matter. Pstack's formal maintenance allows a property
change when comments, tests, changelog, or commit messages establish intended
behavior change. Those sources may explain intent, but do not alone authorize
changing an assurance-records CLAIM or overriding a GATE. Pstack also uses
broader formal-verification terminology; bounded exploration stays `search`
under this pack's convention. Retain its distinction from deductive `formal`
evidence. Preserve the existing fresh-verification procedure rather than
equating a passing tool run or several agreeing reviewers with a claim pass.

The implemented blend remains one optional hunt workflow. Do not import pstack's
Cursor-specific routing, model defaults, automatic skill generation, or
mandatory diagram tooling. The source is
[MIT licensed](https://github.com/cursor/plugins/blob/9580c23696ac8d7abed0c166f2f9918800afb819/pstack/LICENSE);
retain its copyright and license notice if incorporating substantial text or
code. Source inspection supports this adaptation, not a claim that
it finds more bugs. Test that through the focused trial above.
