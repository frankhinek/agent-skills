#!/usr/bin/env bash
# Set up a project to use the linked-records convention with any agent tool.
#
# Usage: bootstrap.sh [--link] [--force] [project-dir]
#   default : copy skills into .agents/skills/ — real files, commit them;
#             works for collaborators and cloud sandboxes (Codex cloud etc.)
#   --link  : symlink instead — local experiments only; don't commit links
#   --force : overwrite vendored skills even if they were locally edited
#
# Re-run any time to refresh the vendored copies from this repo. A checksum
# manifest written at vendor time distinguishes stale-but-pristine copies
# (refreshed freely) from locally edited ones (refused without --force, so
# edits can be merged into this repo first).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)
MANIFEST=".agents/skills/.vendored-manifest"

MODE=copy
FORCE=no
while [ $# -gt 0 ]; do
  case "$1" in
  --link) MODE=link ;;
  --force) FORCE=yes ;;
  *) break ;;
  esac
  shift
done
cd "${1:-.}"

# Checksums of the currently vendored real files, deterministic order.
# Symlinked skill dirs hold no local work and are excluded.
checksum_vendored() {
  for s in "${SKILLS[@]}"; do
    d=".agents/skills/$s"
    { [ -d "$d" ] && [ ! -L "$d" ]; } || continue
    find "$d" -type f | sort
  done | while IFS= read -r f; do cksum "$f"; done
}

current="$(checksum_vendored)"
if [ -n "$current" ] && [ "$FORCE" = "no" ]; then
  if [ ! -f "$MANIFEST" ]; then
    echo "error: vendored skills exist but no manifest was found, so local" >&2
    echo "edits cannot be told apart from staleness. Re-run with --force to" >&2
    echo "overwrite, or remove .agents/skills/ manually first." >&2
    exit 1
  fi
  if [ "$current" != "$(cat "$MANIFEST")" ]; then
    echo "error: vendored skills were edited since they were vendored:" >&2
    diff "$MANIFEST" <(printf '%s\n' "$current") |
      awk '/^[<>]/ {print "  " $NF}' | sort -u >&2
    echo "Merge those edits into the canonical repo, or re-run with --force" >&2
    echo "to discard them." >&2
    exit 1
  fi
fi

mkdir -p .agents/skills
for s in "${SKILLS[@]}"; do
  dst=".agents/skills/$s"
  rm -rf "$dst"
  if [ "$MODE" = "link" ]; then
    ln -sfn "$REPO/skills/$s" "$dst"
  else
    cp -R "$REPO/skills/$s" "$dst"
  fi
done

if [ "$MODE" = "copy" ]; then
  checksum_vendored >"$MANIFEST"
else
  rm -f "$MANIFEST"
fi

POINTER='This project uses the linked-records convention; read
`.agents/skills/linked-records/SKILL.md` before working with `specs/`
directories or code governed by their records.'

if [ ! -f AGENTS.md ]; then
  printf '%s\n' "$POINTER" >AGENTS.md
  echo "created AGENTS.md"
elif ! grep -q "linked-records convention" AGENTS.md; then
  printf '\n%s\n' "$POINTER" >>AGENTS.md
  echo "appended pointer to AGENTS.md"
else
  echo "AGENTS.md already references linked-records"
fi

echo "done ($MODE): .agents/skills/{linked-records,linked-records-claims,linked-records-upkeep}"
