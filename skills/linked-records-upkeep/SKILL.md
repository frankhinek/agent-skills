---
name: linked-records-upkeep
description: Use when explicitly asked to bootstrap linked-records in a project, lint the records corpus, or groom/trim an accumulated one. Not for ordinary implementation work.
---

# Upkeep

Read the `linked-records` skill (`../linked-records/SKILL.md`) first, and
`../linked-records-claims/SKILL.md` when claims are involved. Three
explicit-request workflows: bootstrap, lint, groom.

## Bootstrap

Introduce the convention to an existing project with a useful baseline, not
a transcription of the repository.

1. Survey structure, major components, existing docs, representative code
   and tests. The survey is discovery, not a mandate to fill every category.
2. Create a small initial set: a project-root `ARCH-<project-name>`
   overview; component `ARCH-*` records only where independently useful;
   `REQ-*` and `SPEC-*` only for knowledge passing their thresholds with no
   better existing source of truth. No `GATE-*` and no `CLAIM-*` during
   bootstrap — propose candidates and let the user establish them as
   separate explicit requests. Empty categories are normal.
3. Preserve existing documentation with a distinct purpose; migrate and
   remove only what the new records fully duplicate. Correct editorial
   contradictions; escalate substantive ones.
4. Add to the project's `AGENTS.md` (create it if absent): "This project
   uses the linked-records convention; read
   `.agents/skills/linked-records/SKILL.md` before working with `specs/`
   directories or code governed by their records." Vendor the three skill
   directories into `.agents/skills/` when they are not already present.
5. Finish with the lint pass below.

Never copy secrets or sensitive operational detail into records.

## Lint

Mechanical conformance, checkable without judgment. Report and fix:

- record IDs repository-unique, matching filename and leading
  `# <ID>: <title>` heading
- only defined types (`ARCH`, `REQ`, `SPEC`, `GATE`, `CLAIM`)
- all relative links and referenced IDs resolve; no references to renamed
  or deleted records anywhere in the repo (`rg` the old IDs)
- every `SPEC-*` has its one-sentence `## Record justification`; no source
  code excerpts
- every `GATE-*` has `## Gate` then `## Justification` and no `## Status`
- every `CLAIM-*` record contains only the property statement; any sibling
  evidence directory contains only its claim's evidence
- no index files, tombstones, or redirect stubs
- records live under a `specs/` directory in the scope they govern

Gate defects are reported, not fixed — every gate operation needs the user's
explicit request.

## Groom

Shrink an accumulated corpus while preserving important durable knowledge.
Prefer removing documentation weight over polishing records that should not
exist.

1. Sample N records at random (default 10) before reading any candidates —
   `find . -type f -path '*/specs/*.md' | shuf | head -n "$N"` — and do not
   resample based on apparent quality. Read linked records, nearby code, and
   tests as needed to judge the sample; supporting reads don't count
   against it.
2. For each sampled record ask: would deleting it lose durable knowledge
   that should constrain future work? Does it still meet its type's
   threshold? Does it restate what code, types, tests, or comments already
   show? Does another record own the same subject? Is a code/record drift
   visible against the current implementation?
3. Apply the smallest corpus-preserving outcome: delete, merge into a
   canonical record, trim low-value sections, or keep unchanged. Prefer
   deletion and consolidation over splitting. Update every reference when
   deleting or merging.
4. Grooming authorizes removing redundant or non-qualifying documentation.
   It never authorizes changing intended behavior, architecture, any gate,
   or external requirements — escalate those. Do not modify source code or
   tests; report follow-ups instead.
5. Report: sampled IDs, each outcome with a concise reason, drift findings
   and escalations, and the net record and word-count change.
