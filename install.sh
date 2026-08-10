#!/usr/bin/env bash
# Symlink this repo's skills into agent tools' global skills directories.
#
# Usage: install.sh [extra-skills-dir ...]
#
# The defaults are the tools verified on this machine (Claude Code, Codex,
# Goose) and are skipped when a tool is absent. Any other Agent Skills
# client: pass its global skills directory as an argument — explicit
# targets are attempted first and created if needed. All independent targets
# are attempted; any partial installation produces a nonzero exit. Project-level
# vendoring (vendor.sh) is the universal path and needs no installer.
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
  local target="$1"
  local installed=0
  local already_correct=0
  local skipped=0
  local failed=0
  local s src dst

  if ! mkdir -p "$target"; then
    echo "fail  $target (cannot create target directory)" >&2
    failed=${#SKILLS[@]}
  fi

  if [ "$failed" -eq 0 ]; then
    for s in "${SKILLS[@]}"; do
      src="$REPO/skills/$s"
      dst="$target/$s"

      if [ ! -d "$src" ]; then
        echo "fail  $dst (repository skill is missing)" >&2
        failed=$((failed + 1))
        continue
      fi

      if [ "$src" -ef "$dst" ]; then
        echo "keep  $dst (already correct)"
        already_correct=$((already_correct + 1))
        continue
      fi

      if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        if ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
          echo "skip  $dst (local copy differs from repo; reconcile manually)"
          skipped=$((skipped + 1))
          continue
        fi
        if ! rm -rf "$dst"; then
          echo "fail  $dst (cannot replace identical local copy)" >&2
          failed=$((failed + 1))
          continue
        fi
      fi

      if ln -sfn "$src" "$dst"; then
        echo "link  $dst -> $src"
        installed=$((installed + 1))
      else
        echo "fail  $dst (cannot create symlink)" >&2
        failed=$((failed + 1))
      fi
    done
  fi

  if [ "$skipped" -eq 0 ] && [ "$failed" -eq 0 ]; then
    echo "complete  $target (installed=$installed, already-correct=$already_correct)"
    return 0
  fi

  echo "partial  $target (installed=$installed, already-correct=$already_correct, skipped=$skipped, failed=$failed)"
  return 1
}

overall=0

for dir in "$@"; do
  if ! install_into "$dir"; then
    overall=1
  fi
done

for dir in "${DEFAULTS[@]}"; do
  if [ -d "$(dirname "$dir")" ]; then
    if ! install_into "$dir"; then
      overall=1
    fi
  else
    echo "skip  $dir (tool not present)"
  fi
done

exit "$overall"
