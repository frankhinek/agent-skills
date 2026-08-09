#!/usr/bin/env bash
# Set up a project to use the linked-records convention with any agent tool.
#
# Usage: vendor.sh [--copy|--link|--check] [--force] [project-dir]
#   --copy  : copy skills into .agents/skills/ — the default; real files,
#             commit them;
#             works for collaborators and cloud sandboxes (Codex cloud etc.)
#   --link  : symlink instead — local experiments only; don't commit links
#   --check : read-only status — provenance, local edits, and staleness vs
#             the published repo (git ls-remote); nonzero exit if actionable
#   --force : overwrite vendored skills even if they were locally edited
#
# Copy mode vendors committed content only (it refuses on a dirty skills/
# tree) and stamps the manifest with the source revision and remote, so
# --check can compare against the published HEAD from any machine — no
# local clone of the skills repo needed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)
MANIFEST=".agents/skills/.vendored-manifest"

MODE=copy
MODE_SET=no
FORCE=no
PROJECT_DIR=.
PROJECT_SET=no

usage_error() {
  printf 'error: %s\n' "$1" >&2
  printf 'usage: vendor.sh [--copy|--link|--check] [--force] [project-dir]\n' >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
  --copy | --link | --check)
    requested_mode="${1#--}"
    if [ "$MODE_SET" = yes ] && [ "$MODE" != "$requested_mode" ]; then
      usage_error "conflicting modes: --$MODE and $1"
    fi
    MODE="$requested_mode"
    MODE_SET=yes
    ;;
  --force) FORCE=yes ;;
  -*) usage_error "unknown option: $1" ;;
  *)
    if [ "$PROJECT_SET" = yes ]; then
      usage_error "multiple project directories: $PROJECT_DIR and $1"
    fi
    PROJECT_DIR="$1"
    PROJECT_SET=yes
    ;;
  esac
  shift
done

if [ "$MODE" = check ] && [ "$FORCE" = yes ]; then
  usage_error "--force cannot be used with --check"
fi

cd "$PROJECT_DIR"

# Checksums of the currently vendored real files, deterministic order.
# Symlinked skill dirs hold no local work and are excluded.
checksum_vendored() {
  for s in "${SKILLS[@]}"; do
    d=".agents/skills/$s"
    { [ -d "$d" ] && [ ! -L "$d" ]; } || continue
    find "$d" -type f | sort
  done | while IFS= read -r f; do cksum "$f"; done
}

manifest_field() {
  sed -n "s/^# $1: //p" "$MANIFEST" 2>/dev/null | head -1
}

if [ "$MODE" = "check" ]; then
  status=0
  if [ -L ".agents/skills/${SKILLS[0]}" ]; then
    echo "skills are symlinked (link mode): tracking the repo live, nothing to check"
    exit 0
  fi
  current="$(checksum_vendored)"
  if [ -z "$current" ]; then
    echo "no vendored skills found in $(pwd)"
    exit 0
  fi
  rev="$(manifest_field revision)"
  url="$(manifest_field vendored-from)"
  when="$(manifest_field date)"
  echo "provenance : ${url:-unknown} @ ${rev:-unknown} (${when:-unknown})"
  if [ ! -f "$MANIFEST" ]; then
    echo "local edits: unknown (no manifest)"
    status=1
  elif [ "$current" = "$(grep -v '^#' "$MANIFEST")" ]; then
    echo "local edits: none"
  else
    echo "local edits: YES — files differing from what was vendored:"
    diff <(grep -v '^#' "$MANIFEST") <(printf '%s\n' "$current") |
      awk '/^[<>]/ {print "  " $NF}' | sort -u
    status=1
  fi
  if [ -n "$rev" ] && [ -n "$url" ]; then
    head="$(GIT_TERMINAL_PROMPT=0 git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}')" || head=""
    if [ -z "$head" ]; then
      echo "published  : unknown (remote unreachable)"
    elif [ "$head" = "$rev" ]; then
      echo "published  : current (matches HEAD)"
    else
      echo "published  : STALE — HEAD is $head; re-run vendor.sh to refresh"
      status=1
    fi
  else
    echo "published  : unknown (manifest has no provenance stamp; refresh to add one)"
    status=1
  fi
  exit "$status"
fi

# Copy mode distributes committed content only, so the stamp is truthful.
REV=""
URL=""
if [ "$MODE" = "copy" ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$REPO" status --porcelain -- skills/)" ]; then
    echo "error: uncommitted changes in $REPO/skills/ — commit them first." >&2
    echo "Copy mode vendors committed content only; use --link to iterate." >&2
    exit 1
  fi
  REV="$(git -C "$REPO" rev-parse HEAD)"
  URL="$(git -C "$REPO" remote get-url origin 2>/dev/null |
    sed -E 's#^git@([^:]+):#https://\1/#; s#\.git$##')" || URL=""
fi

# Refuse to discard local edits to vendored copies (see --force).
current="$(checksum_vendored)"
if [ -n "$current" ] && [ "$FORCE" = "no" ]; then
  if [ ! -f "$MANIFEST" ]; then
    echo "error: vendored skills exist but no manifest was found, so local" >&2
    echo "edits cannot be told apart from staleness. Re-run with --force to" >&2
    echo "overwrite, or remove .agents/skills/ manually first." >&2
    exit 1
  fi
  if [ "$current" != "$(grep -v '^#' "$MANIFEST")" ]; then
    echo "error: vendored skills were edited since they were vendored:" >&2
    diff <(grep -v '^#' "$MANIFEST") <(printf '%s\n' "$current") |
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
  {
    if [ -n "$URL" ]; then echo "# vendored-from: $URL"; fi
    if [ -n "$REV" ]; then echo "# revision: $REV"; fi
    echo "# date: $(date +%Y-%m-%d)"
    checksum_vendored
  } >"$MANIFEST"
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
