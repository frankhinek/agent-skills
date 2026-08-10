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
└── linked-records-upkeep/          # bootstrap / lint / groom workflows
    ├── SKILL.md
    └── lint.sh                     # executable mechanical checks (CI-ready)
install.sh                          # symlink skills into each tool's global dir
vendor.sh                           # set up a project (vendor skills + AGENTS.md pointer)
```

## Install (per machine)

```sh
./install.sh
```

Symlinks every skill into the global skills directory of each tool present
on the machine — the defaults (`~/.claude/skills`, `~/.codex/skills`,
`~/.config/goose/skills`) are the tools verified here, skipped when absent.
For any other Agent Skills client, pass its global skills directory as an
argument (e.g. `./install.sh ~/.gemini/antigravity/skills`); explicit
targets are always installed. Idempotent; edit skills here, every tool sees
the change immediately. Project-level vendoring via `vendor.sh` is the
universal path and needs no installer at all.

## New project

```sh
~/Developer/agent-skills/vendor.sh [--copy|--link|--check] [--force] [project-dir]
```

Copies the skills into the project's `.agents/skills/` and writes (or
appends to) `AGENTS.md` with a pointer to the core skill. Commit both: real
files travel with the repo, so cloud agents (Codex cloud tasks and similar
sandboxes that never see your home directory) and collaborators get the
convention too. Re-run to refresh the vendored copies after updating this
repo. Use `--link` for throwaway local experiments (don't commit the links).

Re-runs are guarded by a checksum manifest written at vendor time: a
stale-but-pristine copy refreshes freely, but locally edited vendored
skills are never silently overwritten — vendor.sh refuses and lists the
edited files. Merge those edits into this repo (they're usually
convention improvements worth keeping), then re-run with `--force`.
Options may appear before or after the project directory. Copy mode is the
default; conflicting modes, unknown options, extra directories, and
`--check --force` are rejected before the project is touched.

The manifest is stamped with the source revision, and
`vendor.sh --check` prints a read-only status from any machine:
provenance, local edits, and staleness against the published repo (one
`git ls-remote`, no clone needed; nonzero exit when actionable). Checking
is on demand and updating is deliberate — nothing nags, and nothing
mutates or touches the network outside `--check`. Copy mode vendors
committed content only (use `--link` while iterating on skills locally),
so the stamp is always truthful.

Before checking provenance, `--check` inventories all three expected skill
destinations and their regular `SKILL.md` markers. A coherent install whose
three symlinks point exactly to their matching skills in this repository
succeeds immediately; a coherent all-copy install continues through the
manifest, local-edit, and published revision checks. Missing, mixed, dangling,
wrong-target, markerless, and otherwise invalid installations fail before
provenance or network work and print every skill's state. When all three skills
and the manifest are absent, the install is called out separately as not
installed or the wrong project directory, even if the shared `.agents/skills`
directory contains unrelated skills. Preserve or move only affected
linked-records entries, inspect and merge local work, then reinstall with an
explicit `--copy` or `--link` mode.

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

## Provenance & licensing status

The linked-records skills are a synthesis derived from
[dpc](https://radicle.network/nodes/radicle.dpc.pw/rad%3Az2HR882B4c4mTdAgdt4SozpdeTuMf)'s
Linked Specs convention (`dpc-public-skills` on his Radicle node) and
[maan2003](https://github.com/maan2003/public-skills)'s agentic-claims
skill, with ADR practice as the historical backdrop. The scripts, linter,
and eval suite are original to this repo.

**No license yet.** Both upstreams are unlicensed personal repos, and
relicensing the derived material here is pending their authors'
permission. Until that lands, no reuse rights are granted beyond viewing
and forking under GitHub's terms.

## Conventions for skills in this repo

- Frontmatter carries only the spec-required `name` and `description`.
- Bodies are plain Markdown + portable shell; no harness-specific
  vocabulary or tool names.
- Cross-references between skills use the skill name **and** a relative
  path, so both skill loaders and plain file-readers can follow them.
- The convention is itself a record: when practice exposes a gap, amend the
  skill files and commit.
