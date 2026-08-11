---
name: linked-records
description: Personal convention for durable project knowledge kept as small, linked Markdown records (ARCH, REQ, SPEC, GATE, CLAIM) in specs/ directories. Use when working with such records or code they govern, or when asked to record architecture, requirements, constraints, decisions, or claims. If the project defines its own records convention (e.g. Linked Specs), follow the project's convention instead.
---

# Linked Records

Keep durable project knowledge at the strongest enforcement rung available:
type > schema constraint > lint/CI check > test > record > nothing. Records
are the fallback only when knowledge matters beyond the current change and no
mechanical artifact can own it. Prefer strengthening enforcement.

Ordinary work changes no records by default. A request to document supplies
intent, not qualification; apply the thresholds below. Records are not
planning, changelog, archive, or general documentation. Delete superseded
records; git preserves history.

## Records

Records live in the governed project or package's `specs/` directory. Name
them `<TYPE>-<short-slug>.md`; begin `# <TYPE>-<short-slug>: Title`; keep the
stem repository-unique. No indexes: find IDs with `rg`, links, and code
references. Code/test citations must add rationale. Prefer Markdown links
whose text is the target ID and whose wording names the relationship
(`constrained by`, `refines`, `supersedes`).

Two kinds of record, split by direction of authority:

**Descriptive** records (`ARCH`, `REQ`, `SPEC`, `CLAIM`) report facts governed
elsewhere: implementation governs `ARCH-*`/`SPEC-*`; cited external source and
applicability govern `REQ-*`; `CLAIM-*` wording stays fixed while evidence and
verdict track support. Make only meaning-preserving editorial fixes.
Synchronize record and implementation only when the user requested the end
state and its authority permits it; otherwise surface the conflict.

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
  justification, and checkable acceptance conditions. A requested code end
  state never authorizes changing what is required or when it is satisfied;
  never infer source or applicability changes from code. Retire a named
  requirement record only on explicit user request. Retirement stops
  tracking; it changes neither applicability nor conflicting code's
  compliance.
- `SPEC-*` — a non-local behavioral contract whose implementation is
  necessarily distributed, so no single code artifact can own it. Must carry
  a one-sentence `## Record justification` naming the distributed areas and
  why none is a coherent owner; if that sentence cannot be written honestly,
  the record should not exist. Refer to code by stable identifiers instead of
  source excerpts. Use fenced blocks only for diagrams, with the exact
  lowercase label `text`, `mermaid`, `plantuml`, or `dot`.
- `GATE-*` — a deliberate constraint protected from being helpfully undone:
  the record establishes the constraint. `## Gate` states it precisely;
  `## Justification` explains what it protects (informative context, never an
  additional constraint — escalate ambiguity instead of reading the
  justification normatively).
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

When an agreed end state cannot land atomically, put `## Status` immediately
after a descriptive record's heading: current deviation, applied parts, and
intended resolution. Status describes alignment, never blesses accidental
drift, and never appears on `GATE-*`. A `REQ-*` Status records deviation
against unchanged acceptance conditions.

## Conflicts

When a record blocks work, contradicts another, or disagrees with its
authority or current reality without prior user resolution: stop affected
work, state the conflict and evidence briefly, and let the user decide.
Investigate only enough to explain it; do not research alternatives or draft
rewrites unless asked afterward.

## Maintenance

The `linked-records-claims` skill (`../linked-records-claims/SKILL.md`)
covers claim proofs and adversarial verification. The
`linked-records-upkeep` skill (`../linked-records-upkeep/SKILL.md`) covers
bootstrapping a project, the mechanical lint pass, and grooming an
accumulated corpus. When practice exposes a failure mode this convention did
not anticipate, amend these skill files — the convention is itself a record
and should stay small, current, and truthful.
