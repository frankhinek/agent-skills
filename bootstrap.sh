#!/usr/bin/env bash
# Set up a project to use the linked-records convention with any agent tool.
#
# Usage: bootstrap.sh [--link] [project-dir]
#   default : copy skills into .agents/skills/ — real files, commit them;
#             works for collaborators and cloud sandboxes (Codex cloud etc.)
#   --link  : symlink instead — local experiments only; don't commit links
#
# Re-run any time to refresh the vendored copies from this repo.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)

MODE=copy
if [ "${1:-}" = "--link" ]; then
  MODE=link
  shift
fi
cd "${1:-.}"

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
