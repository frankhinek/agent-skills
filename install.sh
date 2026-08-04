#!/usr/bin/env bash
# Symlink this repo's skills into each agent tool's global skills directory.
# Idempotent: re-run after adding skills to the repo or setting up a new tool.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)
TARGETS=(
  "$HOME/.claude/skills"        # Claude Code
  "$HOME/.codex/skills"         # Codex CLI / ChatGPT desktop
  "$HOME/.config/goose/skills"  # Goose
)

for dir in "${TARGETS[@]}"; do
  if [ ! -d "$(dirname "$dir")" ]; then
    echo "skip  $dir (tool not present)"
    continue
  fi
  mkdir -p "$dir"
  for s in "${SKILLS[@]}"; do
    dst="$dir/$s"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      rm -rf "$dst" # replace a stale real copy with a link to this repo
    fi
    ln -sfn "$REPO/skills/$s" "$dst"
  done
  echo "link  $dir -> $REPO/skills"
done
