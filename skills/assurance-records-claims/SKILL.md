---
name: assurance-records-claims
description: Use when creating, reading, proving, or verifying a CLAIM-* record under the assurance-records convention, or when changes to implementation, models, proof artifacts, schemas, configuration, or toolchains affect an existing claim's evidence.
---

# Claims

Read the `assurance-records` skill (`../assurance-records/SKILL.md`) first.
For an independent verification request, start with
[Verification](#verification-verificationmd) before opening claim evidence.

A claim states one falsifiable, load-bearing
property the code in scope claims to hold — "this named bad thing cannot
happen" or "this invariant is preserved" — precisely enough to judge whether
a change breaks it. Ordinary work treats claims as context to uphold;
proof and verification happen only when explicitly requested or before
recording a `pass`.

Create a claim only on the user's explicit request. When work surfaces a
property that deserves one (a bug a claim would have caught, an invariant
several changes have nearly broken), propose it — do not create it. Do not
claim a feature, a plan, a generic quality goal, or a fact a local type,
constraint, test, or checked proof already establishes completely. A claim
must pay rent: a credible failure mode it guards, a named residual, or a
cross-cutting property whose preservation needs more context than its
implementation and executable evidence show.

The property statement is fixed outside this workflow. An editorial or
documentation pass never rewords a claim — its exact wording is what the
evidence attests — and retiring or deleting a claim and its evidence
requires the user's explicit request, exactly like creating one. A
requested code change that falsifies a claim authorizes neither rewording
nor removal: implement only what was asked, record the falsification, and
escalate.

## Record and evidence layout

The record holds only the property statement — no metadata, rationale,
proof, verdict, or status. Evidence lives in a sibling directory:

```text
specs/
├── CLAIM-single-writer.md
└── CLAIM-single-writer/
    ├── proof.md          # evidence and the argument connecting it
    └── verification.md   # independent verifier's result
```

A task that only needs the claim as implementation context needs neither
file. Executable models, proofs, and checks stay in their normal project
locations; link them from the evidence files rather than copying them here.

## Proof (proof.md)

Derive from the current code, tests, configuration, and deployment model —
never from memory. Structure:

1. **Scope** — the code, configuration, interfaces, and execution paths the
   argument reads.
2. **Model and quantifiers** — inputs, actors, failure points, concurrency,
   and the exact durable predicate. Enumerate only domains that can be
   mechanically regenerated and diffed.
3. **Axioms** — every trusted external premise and where the guarantee
   bottoms out (crypto hardness, OS behavior, single-instance locks). The
   classic defect is the smuggled premise a lemma uses but never states.
4. **Argument** — short numbered lemmas connecting evidence and axioms to
   the property, each citing its sources and labeled with its rung. Refer to
   checked formal results; explain only connections they do not establish.
5. **Residuals** — executions deliberately outside the claim's quantifiers,
   with reasons. A counterexample inside the stated property falsifies the
   proof; filing it as a residual is an argument bug.
6. **Weakest links** — the least mechanically enforced lemmas and how to
   strengthen them.

### Residuals and assumptions

For each residual, identify the claim qualifier that excludes it; cite the
existing user decision where acceptance of that boundary was required.
An assumption in the argument cannot silently narrow the fixed claim.

Accepting new residual risk or a premise that materially narrows the guarantee
belongs to the user. Retain the boundary established by existing instructions
or recorded decisions; report uncovered behavior as an evidence gap. Request
a new decision only when proposing to change that boundary, never to reconfirm
the existing guarantee. Technical premises supported by project contracts or
evidence need no renewed approval. Documenting a premise does not establish
its truth or authorize a weaker guarantee.

Until the evidence covers the claim, keep the verdict provisional; an actual
counterexample within its scope is falsified, never an accepted residual.
An authorized scope change must be reflected explicitly in the claim through
this workflow before a narrower argument can support it. Acceptance alone
does not establish a pass or override a governing gate or requirement.

### Rungs

Label each lemma by what checks or enforces it, not what the code gestures
at. These are evidence kinds, not a total ordering of strength:

- `type` — compiler-checked; misuse does not build
- `schema` — database or serialization constraint; violation fails the write
- `lint` — a CI check fails
- `test` — a named test fails
- `formal` — a machine-checked deductive result for an exact proposition
  under explicit premises. Record its theorem or obligation identifier,
  artifact and revision, checker/toolchain version, reproducible command and
  observed result, and assumptions or trusted components. State whether it
  covers production code, a translation, or a separate model; justify the
  correspondence and identify remaining gaps. Audit admitted obligations and
  added axioms: an assumed conclusion supplies no proof of that conclusion.
  A missing checker, timeout, or unsuccessful proof attempt is incomplete
  evidence, not a counterexample. Finite or sampled exploration uses `search`.
- `search` — a bounded exhaustive or generated exploration of behavior. State
  whether it is exhaustive or sampled, its bounds or budget and reproducibility
  inputs, the oracle or property being checked, a named negative control it
  rejects, and how the harness and oracle correspond to production code. A
  pass means no counterexample in the explored space, never "cannot happen"
- `enum` — an enumeration, regenerated on every check, never trusted as
  written
- `code` — a local reading of one guard or ordering
- `claim` — the exact conclusion of another current, verified claim,
  imported under the composition rules below
- `axiom` — trusted, not checked

Under concurrency, a one-time gate check does not establish an invariant: a
lemma needs the check and the guarded action in one critical section, or a
durable recheck, and must say which.

## Composing claims

In `proof.md`, link each imported claim and state the exact conclusion used.
Keep imports acyclic. The effective scope includes the local evidence plus
imported records, verdicts, and their relevant scopes recursively. Carry
forward their assumptions and check that definitions, interfaces, execution
models, and assumptions are compatible.

An imported pass must cover the state relied on by the parent. Verify the
argument connecting imports, including paths between or outside their scopes;
passing components alone do not establish the parent's property. Record uses
of imported conclusions as `claim` and label the connecting steps separately.
For the sufficiency attack, grant every imported conclusion exactly as stated
and try to construct an execution where the parent still fails. Check missing
connections even when all premises are compatible. This thought experiment
does not discharge the separate obligation to establish imported support.
A parent pass requires current support for each relied-on import and an
independent check of the composition.

Formal tools own dependencies inside their checked artifacts. Claim imports
track connections across verification boundaries; cite the tool's checked
result and dependency coverage instead of maintaining a duplicate theorem
graph. A successful formal check leaves production correspondence and
deployment assumptions to be established wherever the check does not cover them.

## Verification (verification.md)

The author's derivation alone never yields a pass. The author or coordinator
arranges an independent verifier in a fresh context, without inherited author
discussion or earlier review conclusions. An agent already assigned independent
verification performs this procedure itself; loading this skill does not require
another reviewer. If the necessary independence or tooling is unavailable,
record the limitation and keep unsupported evidence provisional, preserving
unresolved falsifications.

1. Select initial inputs by filename. Exclude earlier verification reports and
   attack lists from bulk content reads and searches. Assess the current claim,
   proof, governing boundaries, implementation, and executable evidence. Record
   fresh attacks and findings in the conversation or permitted scratch space;
   confirm they were recorded before opening historical reports. A failed write
   does not complete this step. If prior conclusions are already in context,
   disclose the exposure and arrange a fresh assessment before claiming this
   phase is complete; without it, no new pass is supported.
2. Reconcile with previous findings and counterexamples, including witnesses the
   fresh assessment missed. Rerun relevant witnesses against the current state
   or inspect reproducible run evidence covering it. Resolve each material
   finding; inability to reproduce because a check is unavailable is not repair.
3. Write the combined receipt in `verification.md` only after reconciliation.
   Distinguish fresh findings from historical checks; retain unresolved findings
   and useful witness links. A fresh assessment alone supplies no final pass.

Attack the argument, not the conclusion —
misread guards, lock scopes and orderings at line level, non-exhaustive case
splits, smuggled axioms, enumerations regenerated and diffed, residual
filing, including unauthorized narrowing through assumptions or exclusions.
For formal evidence, reproduce the check or inspect a reproducible
recorded run covering the relevant state, and attack statement adequacy,
assumptions, and correspondence to production. Agent review cannot substitute
for the checker or extend the proposition it established. Record: the revision
checked, verifier and date, evidence kinds, commands and observed results or
linked run evidence, what was inspected,
attacks performed, the result, and every material finding or repair.

Verdicts: `pass` means the argument survived attack at that revision — never
"cannot happen". Keep formal results, explored bounds, and reviewed connections
distinct in that argument. `provisional` means verification is incomplete or
evidence is stale, unavailable, or insufficient. `falsified` names a
counterexample to the stated claim and stands until the
discrepancy is resolved; never adjust a claim to match accidental behavior
without an explicit request.

Record each verdict on its own line as exactly `Result: pass`,
`Result: provisional`, or `Result: falsified`. The last such line in
`verification.md` is the current machine-readable verdict; put dates,
rationale, and counterexamples on separate prose lines.

## Counterexamples and repair

For each counterexample, retain its revision, relevant conditions, inputs or
schedule, expected property, and observed violation in the evidence. Link an
executable witness or regression test in its normal project location when
practical. An argument defect or a model counterexample without an established
connection to the implementation leaves support provisional; use falsified
only for a counterexample within the stated claim's scope.

When repairing an affected failure, rerun its witness and record the observed
result and why the failure mechanism is eliminated. Adapt an obsolete witness
to changed interfaces while preserving the triggering conditions and property;
retain useful regression coverage. A missing tool, broken reproducer, or
unexplained failure to reproduce does not resolve a known falsification.
Account for every unresolved counterexample: fixing one cannot clear another.
Once all known violations are resolved, use provisional until the required
independent verification completes. Repair authorizes focused witness checks,
not an unsolicited proof campaign. Preserve useful reproduction and repair
evidence when updating the current verdict; retirement follows the rules below.

## Staleness and promotion

When a change intersects a proof's scope, model, axioms, cited tests, or
imported claims, the same change updates the affected coverage and, if the
existing verdict no longer covers the source state, demotes it to
`provisional` with a note of what needs re-verification. Stale evidence does
not by itself block a change; fresh verification is required only on request
or before recording a new `pass`.

A `search` lemma becomes stale when relevant code, harness, oracle or model,
generator, corpus, or search configuration changes beyond what the recorded
run covers. Restore it only by rerunning its negative controls and search
against the current revision.

An affected `formal` lemma needs reassessment when its statement, definitions,
premises, proof artifacts, checker/toolchain or options, or production
correspondence change beyond the recorded check's coverage. Recheck the affected
obligations and connections before restoring support. An unchanged passing model
cannot cover a changed deployment assumption by itself. Unrelated revisions
alone do not invalidate evidence whose coverage still applies.

Propagate lost support through every affected importing claim, transitively,
even when its local code is unchanged. Record the dependency and restoration
work in each affected verdict; keep unsupported passes provisional. A
falsified dependency does not by itself falsify every parent: that requires a
counterexample to the parent's property. Preserve existing falsifications.
Recheck dependencies before restoring a parent pass. Staleness maintenance
does not authorize a fresh proof campaign or a claim-statement change.

Repeated staleness is promotion pressure: replace an enumeration with a lint
or test, a code-reading lemma with a focused test, a runtime convention with
a type or schema constraint. A healthy proof shrinks toward pointers at
machine-checked facts. When a claim is retired, carry decision-relevant
counterexamples into replacement evidence if needed, then delete the record
and its evidence directory.
