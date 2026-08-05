#!/usr/bin/env bash
# Symlink this repo's skills into agent tools' global skills directories.
#
# Usage: install.sh [extra-skills-dir ...]
#
# The defaults are the tools verified on this machine (Claude Code, Codex,
# Goose) and are skipped when a tool is absent. Any other Agent Skills
# client: pass its global skills directory as an argument — explicit
# targets are always installed, created if needed. Project-level vendoring
# (vendor.sh) is the universal path and needs no installer.
# Idempotent: re-run after adding skills, tools, or targets.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)
DEFAULTS=(
  "$HOME/.claude/skills"        # Claude Code
  "$HOME/.codex/skills"         # Codex CLI / ChatGPT desktop
  "$HOME/.config/goose/skills"  # Goose
)

install_into() {
  mkdir -p "$1"
  for s in "${SKILLS[@]}"; do
    dst="$1/$s"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      if diff -rq "$REPO/skills/$s" "$dst" >/dev/null 2>&1; then
        rm -rf "$dst" # identical to the repo copy: safe to replace with a link
      else
        echo "skip  $dst (local copy differs from repo; reconcile manually)"
        continue
      fi
    fi
    ln -sfn "$REPO/skills/$s" "$dst"
  done
  echo "link  $1 -> $REPO/skills"
}

for dir in "${DEFAULTS[@]}"; do
  if [ -d "$(dirname "$dir")" ]; then
    install_into "$dir"
  else
    echo "skip  $dir (tool not present)"
  fi
done

for dir in "$@"; do
  install_into "$dir"
done
