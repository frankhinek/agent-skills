---
name: linked-records-claims
description: Use when creating, reading, proving, or verifying a CLAIM-* record under the linked-records convention, or when a change touches code an existing claim's evidence depends on.
---

# Claims

Read the `linked-records` skill (`../linked-records/SKILL.md`) first. A
claim states one falsifiable, load-bearing
property the code in scope claims to hold — "this named bad thing cannot
happen" or "this invariant is preserved" — precisely enough to judge whether
a change breaks it. Ordinary work treats claims as context to uphold;
proof and verification happen only when explicitly requested or before
recording a `pass`.

Create a claim only on the user's explicit request. When work surfaces a
property that deserves one (a bug a claim would have caught, an invariant
several changes have nearly broken), propose it — do not create it. Do not
claim a feature, a plan, a generic quality goal, or a fact a local type,
constraint, or test already establishes. A claim must pay rent: a credible
failure mode it guards, a named residual, or a cross-cutting property whose
preservation needs more context than its implementation shows.

## Record and evidence layout

The record holds only the property statement — no metadata, rationale,
proof, verdict, or status. Evidence lives in a sibling directory:

```text
specs/
├── CLAIM-single-writer.md
└── CLAIM-single-writer/
    ├── proof.md          # author's derivation
    └── verification.md   # independent verifier's result
```

A task that only needs the claim as implementation context needs neither
file.

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
4. **Argument** — short numbered lemmas from axioms and code to the
   property, each citing its sources and labeled with its rung.
5. **Residuals** — executions deliberately outside the claim's quantifiers,
   with reasons. A counterexample inside the stated property falsifies the
   proof; filing it as a residual is an argument bug.
6. **Weakest links** — the least mechanically enforced lemmas and how to
   strengthen them.

### Rungs

Label each lemma by what mechanically catches its regression, not what the
code gestures at:

- `type` — compiler-checked; misuse does not build
- `schema` — database or serialization constraint; violation fails the write
- `lint` — a CI check fails
- `test` — a named test fails
- `enum` — an enumeration, regenerated on every check, never trusted as
  written
- `code` — a local reading of one guard or ordering
- `claim` — the exact conclusion of another current, verified claim (link
  it; keep claim dependencies acyclic)
- `axiom` — trusted, not checked

Under concurrency, a one-time gate check does not establish an invariant: a
lemma needs the check and the guarded action in one critical section, or a
durable recheck, and must say which.

## Verification (verification.md)

The author's derivation alone never yields a pass. Spawn a separate agent
with an adversarial prompt: attack the argument, not the conclusion —
misread guards, lock scopes and orderings at line level, non-exhaustive case
splits, smuggled axioms, enumerations regenerated and diffed, residual
filing. Record: the revision checked, verifier and date, what was inspected,
attacks performed, the result, and every material finding or repair.

Verdicts: `pass` means the argument survived attack at that revision — never
"cannot happen". `provisional` means verification is incomplete or evidence
is stale. `falsified` names the counterexample and stands until the
discrepancy is resolved; never adjust a claim to match accidental behavior
without an explicit request.

## Staleness and promotion

When a change intersects a proof's scope, model, axioms, cited tests, or
imported claims, the same change updates the affected coverage and, if the
existing verdict no longer covers the source state, demotes it to
`provisional` with a note of what needs re-verification. Stale evidence does
not by itself block a change; fresh verification is required only on request
or before recording a new `pass`.

Repeated staleness is promotion pressure: replace an enumeration with a lint
or test, a code-reading lemma with a focused test, a runtime convention with
a type or schema constraint. A healthy proof shrinks toward pointers at
machine-checked facts. When a claim is retired, carry decision-relevant
counterexamples into replacement evidence if needed, then delete the record
and its evidence directory.
