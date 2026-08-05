# agent-skills

Frank's personal agent skills, usable from any tool that reads the
[Agent Skills](https://agentskills.io) `SKILL.md` format (Claude Code,
Codex CLI / ChatGPT, Goose, Gemini CLI, Cursor, …) or a plain `AGENTS.md`
pointer.

The main content is **linked-records**: a convention for durable project
knowledge as small, linked Markdown records (`ARCH`, `REQ`, `SPEC`, `GATE`,
`CLAIM`) in `specs/` directories. It is a personal synthesis of dpc's
Linked Specs (GATE-era), maan2003's agentic-claims, and the useful residue
of ADR practice. Start with [skills/linked-records/SKILL.md](skills/linked-records/SKILL.md).

## Layout

```
skills/
├── linked-records/SKILL.md         # core convention: record types, authority rules
├── linked-records-claims/SKILL.md  # claim proofs + adversarial verification
└── linked-records-upkeep/SKILL.md  # bootstrap / lint / groom workflows
install.sh                          # symlink skills into each tool's global dir
bootstrap.sh                        # set up a project (vendor skills + AGENTS.md pointer)
```

## Install (per machine)

```sh
./install.sh
```

Symlinks every skill into the global skills directory of each tool present
on the machine (`~/.claude/skills`, `~/.codex/skills`,
`~/.config/goose/skills`). Idempotent; edit skills here, every tool sees the
change immediately.

## New project

```sh
~/Developer/agent-skills/bootstrap.sh [project-dir]
```

Copies the skills into the project's `.agents/skills/` and writes (or
appends to) `AGENTS.md` with a pointer to the core skill. Commit both: real
files travel with the repo, so cloud agents (Codex cloud tasks and similar
sandboxes that never see your home directory) and collaborators get the
convention too. Re-run to refresh the vendored copies after updating this
repo. Use `--link` for throwaway local experiments (don't commit the links).

Re-runs are guarded by a checksum manifest written at vendor time: a
stale-but-pristine copy refreshes freely, but locally edited vendored
skills are never silently overwritten — bootstrap refuses and lists the
edited files. Merge those edits into this repo (they're usually
convention improvements worth keeping), then re-run with `--force`.

The manifest is stamped with the source revision, and
`bootstrap.sh --check` prints a read-only status from any machine:
provenance, local edits, and staleness against the published repo (one
`git ls-remote`, no clone needed; nonzero exit when actionable). Checking
is on demand and updating is deliberate — nothing nags, and nothing
mutates or touches the network outside `--check`. Copy mode vendors
committed content only (use `--link` while iterating on skills locally),
so the stamp is always truthful.

## Using it day to day

The system is deliberately inert: agents never create gates or claims on
their own, and ordinary feature work should produce **no record changes**.
The value comes from a few explicit moves at the right moments:

| Moment | Say to your agent |
|---|---|
| Project has real code, no records yet | "bootstrap linked-records" — surveys the code, writes the initial `ARCH-*` baseline |
| You make a decision that must stick ("local-only, no cloud sync") | "establish a gate: \<constraint\>, because \<goal\>" — agents can no longer undo it without you |
| A property's failure would really hurt ("payments can't double-apply") | "create a claim: \<property\>" — future changes treat it as an invariant to uphold |
| You want actual evidence (pre-release, after a scary refactor) | "prove and verify CLAIM-x" — written proof plus an independent adversarial check |
| Before a PR / end of session | "lint the records" — broken links, missing justifications, code/record drift |
| Every month or so | "groom the records" — random-sample trim of stale or low-value records |

When an agent stops and reports that a record conflicts with your request,
that is the system working. Make the call — amend the record, change the
request — rather than saying "just make it work"; overridden escalations
teach the corpus to be ignored.

Anti-goals: don't ask for broad documentation ("document this project") —
the skill thresholds are built to refuse it. Don't establish gates during
bootstrap — gate decisions as you actually make them, while the reason is
fresh. A small corpus is a healthy corpus; empty categories are normal.

When the convention itself gets in your way, edit the skills in this repo,
commit, push — every tool sees the change immediately.

## How each tool picks it up

- **Skill-aware tools** (Claude Code, Codex, Goose, and other Agent Skills
  adopters) discover the `SKILL.md` files from their global dir or the
  project's `.agents/skills/` and load them when the description matches
  the task.
- **Everything else** falls back to the `AGENTS.md` pointer: any agent that
  can read files can follow "read `.agents/skills/linked-records/SKILL.md`
  first." For a tool that reads a different hints file (e.g. Goose's
  `.goosehints`), a one-line "Read AGENTS.md" suffices.

## Conventions for skills in this repo

- Frontmatter carries only the spec-required `name` and `description`.
- Bodies are plain Markdown + portable shell; no harness-specific
  vocabulary or tool names.
- Cross-references between skills use the skill name **and** a relative
  path, so both skill loaders and plain file-readers can follow them.
- The convention is itself a record: when practice exposes a gap, amend the
  skill files and commit.
