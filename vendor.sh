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
MANIFEST_FORMAT=2

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

source "$REPO/lib/vendor-inventory.sh"

if [ "$MODE" = "check" ]; then
  SKILL_STATES=()
  linked_count=0
  copied_count=0
  missing_count=0
  for s in "${SKILLS[@]}"; do
    d=".agents/skills/$s"
    state=invalid
    if [ -L "$d" ]; then
      link_target="$(readlink "$d" 2>/dev/null || true)"
      if [ "$link_target" = "$REPO/skills/$s" ] && [ -d "$d" ] && [ -f "$d/SKILL.md" ]; then
        state=linked
        linked_count=$((linked_count + 1))
      fi
    elif [ -d "$d" ] && [ -f "$d/SKILL.md" ]; then
      state=copied
      copied_count=$((copied_count + 1))
    elif [ ! -e "$d" ]; then
      state=missing
      missing_count=$((missing_count + 1))
    fi
    SKILL_STATES+=("$state")
  done

  if [ "$linked_count" -eq "${#SKILLS[@]}" ]; then
    echo "skills are symlinked (link mode): tracking the repo live, nothing to check"
    exit 0
  fi
  if [ "$copied_count" -ne "${#SKILLS[@]}" ]; then
    if [ "$missing_count" -eq "${#SKILLS[@]}" ] && [ ! -f "$MANIFEST" ]; then
      echo "error: linked-records skills are not installed here; this may be the wrong project directory." >&2
    else
      echo "error: incoherent linked-records vendoring state." >&2
    fi
    echo "skill states:" >&2
    for i in "${!SKILLS[@]}"; do
      printf '  %s: %s\n' "${SKILLS[$i]}" "${SKILL_STATES[$i]}" >&2
    done
    echo "Preserve or move only affected linked-records entries under .agents/skills before recovery." >&2
    echo "Inspect and merge any local work into the canonical skills repository." >&2
    echo "Then reinstall with an explicit mode: vendor.sh --copy PROJECT_DIR or vendor.sh --link PROJECT_DIR." >&2
    exit 1
  fi

  status=0
  rev="$(manifest_field revision)"
  url="$(manifest_field vendored-from)"
  when="$(manifest_field date)"
  manifest_format_state=invalid
  if manifest_format="$(manifest_format_value)"; then
    manifest_format_state=valid
  else
    manifest_format_status=$?
    if [ "$manifest_format_status" -eq 1 ]; then
      manifest_format_state=legacy
    fi
  fi
  echo "provenance : ${url:-unknown} @ ${rev:-unknown} (${when:-unknown})"

  inventory_ok=yes
  if current="$(inventory_vendored)"; then
    :
  else
    inventory_ok=no
    status=1
  fi
  if [ ! -f "$MANIFEST" ]; then
    echo "local edits: unknown (no manifest)"
    status=1
  elif [ "$inventory_ok" = no ]; then
    echo "local edits: unknown (inventory failed)"
  elif [ "$manifest_format_state" = legacy ]; then
    echo "local edits: unknown (legacy manifest format)"
    status=1
  elif [ "$manifest_format_state" = invalid ]; then
    echo "local edits: unknown (invalid manifest format)"
    status=1
  elif [ "$manifest_format" != "$MANIFEST_FORMAT" ]; then
    echo "local edits: unknown (unsupported manifest format $manifest_format)"
    status=1
  elif ! expected="$(manifest_inventory)" ||
    ! printf '%s\n' "$expected" | validate_inventory; then
    echo "local edits: unknown (invalid manifest inventory)"
    status=1
  elif [ "$current" = "$expected" ]; then
    echo "local edits: none"
  else
    echo "local edits: YES — entries differing from what was vendored:"
    if report_inventory_changes "$expected" "$current"; then
      status=1
    else
      comparison_status=$?
      echo "local edit details: unavailable (comparison failed)"
      status="$comparison_status"
    fi
  fi
  if [ -n "$rev" ] && [ -n "$url" ]; then
    head="$(GIT_TERMINAL_PROMPT=0 git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}')" || head=""
    if [ -z "$head" ]; then
      echo "published  : unknown (remote unreachable)"
    elif [ "$head" = "$rev" ]; then
      echo "published  : current (matches HEAD)"
    else
      echo "published  : STALE — HEAD is $head; re-run vendor.sh to refresh"
      [ "$status" -ne 0 ] || status=1
    fi
  else
    echo "published  : unknown (manifest has no provenance stamp; refresh to add one)"
    [ "$status" -ne 0 ] || status=1
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

# Refuse to discard local edits to vendored copies (see --force). Unsupported
# live entries and inventory errors are never force-overridden: remove or
# preserve them explicitly before asking the script to replace the tree.
if current="$(inventory_vendored)"; then
  :
else
  echo "error: cannot safely inventory the existing vendored skills." >&2
  exit 1
fi
if { [ -n "$current" ] || [ -f "$MANIFEST" ]; } && [ "$FORCE" = "no" ]; then
  if [ ! -f "$MANIFEST" ]; then
    echo "error: vendored skills exist but no manifest was found, so local" >&2
    echo "edits cannot be told apart from staleness. Re-run with --force to" >&2
    echo "overwrite, or remove .agents/skills/ manually first." >&2
    exit 1
  fi
  manifest_format_state=invalid
  if manifest_format="$(manifest_format_value)"; then
    manifest_format_state=valid
  else
    manifest_format_status=$?
    if [ "$manifest_format_status" -eq 1 ]; then
      manifest_format_state=legacy
    fi
  fi
  if [ "$manifest_format_state" = legacy ]; then
    echo "error: the vendored manifest uses the legacy unversioned format," >&2
    echo "which cannot prove that executable state, links, or directories are pristine." >&2
    echo "Inspect and preserve local work, then re-run with --force to replace it." >&2
    exit 1
  fi
  if [ "$manifest_format_state" = invalid ]; then
    echo "error: the vendored manifest has duplicate or malformed format headers." >&2
    echo "Inspect and preserve local work before replacing this installation." >&2
    exit 1
  fi
  if [ "$manifest_format" != "$MANIFEST_FORMAT" ]; then
    echo "error: unsupported vendored manifest format: $manifest_format" >&2
    echo "Inspect and preserve local work before replacing this installation." >&2
    exit 1
  fi
  expected="$(manifest_inventory)"
  if ! printf '%s\n' "$expected" | validate_inventory; then
    echo "error: the vendored manifest inventory is invalid." >&2
    echo "Inspect and preserve local work before replacing this installation." >&2
    exit 1
  fi
  if [ "$current" != "$expected" ]; then
    echo "error: vendored skills were edited since they were vendored:" >&2
    if report_inventory_changes "$expected" "$current" >&2; then
      :
    else
      comparison_status=$?
      echo "error: local edit details are unavailable." >&2
      exit "$comparison_status"
    fi
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
  if current="$(inventory_vendored)"; then
    :
  else
    rm -f "$MANIFEST"
    echo "error: copied skills could not be inventoried; no manifest was written." >&2
    exit 1
  fi
  {
    echo "# manifest-format: $MANIFEST_FORMAT"
    if [ -n "$URL" ]; then echo "# vendored-from: $URL"; fi
    if [ -n "$REV" ]; then echo "# revision: $REV"; fi
    echo "# date: $(date +%Y-%m-%d)"
    printf '%s\n' "$current"
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
