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
