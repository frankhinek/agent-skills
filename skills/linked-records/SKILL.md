---
name: linked-records
description: Personal convention for durable project knowledge kept as small, linked Markdown records (ARCH, REQ, SPEC, GATE, CLAIM) in specs/ directories. Use when working with such records or code they govern, or when asked to record architecture, requirements, constraints, decisions, or claims. If the project defines its own records convention (e.g. Linked Specs), follow the project's convention instead.
---

# Linked Records

Durable project knowledge lives at the strongest enforcement rung available:
type > schema constraint > lint/CI check > test > record > nothing. A record
is the fallback for knowledge that matters beyond the current change and that
no mechanical artifact can own. Before writing one, ask whether a type, a
constraint, a lint, or a test could own the knowledge instead; prefer
strengthening enforcement over describing behavior.

The default outcome of ordinary work is no record change. A request to
document something supplies intent, not qualification — each type below has
its own threshold. Records are not a planning system, changelog, historical
archive, or general documentation. Git history is the archive: superseded
records are deleted, not tombstoned.

## Records

Records live in a `specs/` directory inside the project or package they
govern, named `<TYPE>-<short-slug>.md`, beginning `# <TYPE>-<short-slug>:
Title`. The filename stem is the record ID; keep it repository-unique. No
index files — IDs are found by search (`rg`), links, and references from
code. Cite record IDs from code and tests where the pointer adds rationale,
never as ceremony. Prefer Markdown links with the target ID as link text and
accurate relationship wording (`constrained by`, `refines`, `supersedes`).

Two kinds of record, split by direction of authority:

**Descriptive** records (`ARCH`, `REQ`, `SPEC`, `CLAIM`) describe the current
system and must agree with the code. When one disagrees with reality, do not
silently rewrite either side: fix editorial errors freely (except in
`CLAIM-*` records, whose wording is bound to their evidence), synchronize to
an end state the user already explicitly requested, and surface anything
else as a conflict before proceeding.

**Normative** records (`GATE`) bind future work. A gate never yields to code,
convenience, or agent judgment; it changes only when the user explicitly
requests an operation (establish, amend, revoke, rename) on that named gate.
A task that merely conflicts with a gate is not authorization — report the
conflict and leave the gate unchanged.

### Types

- `ARCH-*` — current shape: components, boundaries, dependency direction,
  ownership, flows, trust boundaries, invariants. The default overview is
  `ARCH-<project-name>`. A map, not an implementation inventory.
- `REQ-*` — an externally imposed obligation: its source, strength,
  justification, and acceptance conditions concrete enough to check a new
  surface or feature against.
- `SPEC-*` — a non-local behavioral contract whose implementation is
  necessarily distributed, so no single code artifact can own it. Must carry
  a one-sentence `## Record justification` naming the distributed areas and
  why none is a coherent owner; if that sentence cannot be written honestly,
  the record should not exist. No source code excerpts — refer to code by
  stable identifiers.
- `GATE-*` — a deliberate constraint protected from being helpfully undone:
  `## Gate` states the constraint precisely; `## Justification` explains what
  it protects (informative context, never an additional constraint —
  escalate ambiguity instead of reading the justification normatively).
- `CLAIM-*` — one falsifiable, load-bearing property the code claims to
  hold, stated in a few sentences with its material qualifiers (protected
  state, boundary, concurrency, adversary). Proof and verification live in a
  sibling directory, and the claim's exact wording is what that evidence
  attests: never reword a claim in an editorial or documentation pass, and
  retire one only on the user's explicit request. Every claim-record change
  goes through the `linked-records-claims` skill
  (`../linked-records-claims/SKILL.md`) — read it before creating, proving,
  verifying, or retiring one.

An `ARCH-*` or `SPEC-*` may end with a selective `## Alternatives` section:
designs considered, why the current one won, whether they remain viable.
Keep it curated — this is the one place decision context is preserved
outside git history, and it must not become a decision-process narrative.

## Gradual change

When an agreed end state cannot land atomically, a descriptive record takes
a `## Status` section immediately after its heading: what currently
deviates, which parts already apply, and the intended resolution. Status
describes alignment, never blesses accidental drift, and never appears on a
`GATE-*`.

## Conflicts

When a record blocks the requested work, contradicts another record, or
disagrees with code in a way the user has not already resolved: stop the
affected work, state the conflict in a few sentences with the evidence, and
let the user decide. Investigate only enough to explain the conflict — no
research spirals, alternative exploration, or drafted rewrites unless
explicitly asked afterward.

## Maintenance

The `linked-records-claims` skill (`../linked-records-claims/SKILL.md`)
covers claim proofs and adversarial verification. The
`linked-records-upkeep` skill (`../linked-records-upkeep/SKILL.md`) covers
bootstrapping a project, the mechanical lint pass, and grooming an
accumulated corpus. When practice exposes a failure mode this convention did
not anticipate, amend these skill files — the convention is itself a record
and should stay small, current, and truthful.
