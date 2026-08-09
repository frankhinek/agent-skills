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

The mechanical checks are owned by `lint.sh`, bundled beside this skill
file. Run it against the project root:

    lint.sh [project-root]

It prints `path: [check] message` findings. A completed scan exits 0 when
clean or 1 when findings exist; invocation or scratch-setup failures exit
2. The mechanical scan covers: record naming and defined types;
filename/heading/ID
agreement and repository uniqueness; resolvable relative links;
references to nonexistent records; exactly one non-empty `SPEC-*`
justification section and diagram fences labeled `text`, `mermaid`,
`plantuml`, or `dot`; `GATE-*` section shape; `CLAIM-*` records without
headings or recognizable `Proof:`/`Verdict:` labels; claim evidence-directory
shape; explicit tombstone markers; index-like files and stray directories in
`specs/`. Fix what it reports — these are the convention's mechanical floor,
not judgment calls.

The reference scan reads regular text files outside `.git/`, `.agents/`,
`node_modules/`, `build/`, `dist/`, `.venv/`, `venv/`, and `vendor/`. Binary
and nonregular files are outside that scan.

Then the checks that still need reading:

- descriptive records agree with the code they describe
- each record still meets its type's qualification threshold
- each `SPEC-*` justification is one honest sentence naming the distributed
  areas and why none is a coherent owner
- each permitted `SPEC-*` fence contains a diagram, not source code
- each `CLAIM-*` contains only its property statement, with no disguised
  rationale, proof, verdict, status, or other metadata
- no record functions as an implicit or euphemistic tombstone
- `## Status` sections are current-state summaries, not progress logs
- `## Alternatives` sections stay selective and current
- links and code citations add rationale, not ceremony

Gate defects are reported, not fixed — every gate operation needs the user's
explicit request.

## Groom

Shrink an accumulated corpus while preserving important durable knowledge.
Prefer removing documentation weight over polishing records that should not
exist.

1. Select a uniform random sample of N records (default 10) from
   `find . -type f -path '*/specs/*.md'` by any available means
   (`sort -R`, `shuf`, or equivalent), and capture the sample before
   reading any candidate. Do not resample based on apparent quality. Read
   linked records, nearby code, and tests as needed to judge the sample;
   supporting reads don't count against it.
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
