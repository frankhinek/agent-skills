#!/usr/bin/env bash
# Set up a project to use the linked-records convention with any agent tool.
#
# Usage: vendor.sh [--copy|--link|--check] [--force] [project-dir]
#   --copy  : copy skills into .agents/skills/ — the default; real files,
#             commit them;
#             works for collaborators and cloud sandboxes (Codex cloud etc.)
#   --link  : symlink instead — local experiments only; don't commit links
#   --check : read-only status — provenance, local edits, and managed-payload
#             staleness vs the published repo; nonzero exit if actionable
#   --force : overwrite vendored skills even if they were locally edited
#
# Copy mode vendors committed content only (it refuses on a dirty skills/
# tree) and stamps the manifest with source and payload identities. --check
# compares payloads when the published HEAD object is locally available.
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
source "$REPO/lib/vendor-provenance.sh"
source "$REPO/lib/vendor-transaction.sh"

# An updater transaction outranks ordinary link/copy classification. Checks are
# read-only; a mutating invocation performs at most recovery and asks for a
# deliberate rerun before starting new work.
if ! vendor_transaction_handle_existing "$MODE"; then
  exit 1
fi

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
  payload_id=""
  if [ ! -f "$MANIFEST" ]; then
    rev=""
    url=""
    when=""
    provenance_state=no-manifest
    payload_id_state=no-manifest
    manifest_format_state=no-manifest
  else
    rev="$(manifest_field revision)"
    when="$(manifest_field date)"
    provenance_state=invalid
    url=""
    if url="$(manifest_provenance_value)"; then
      provenance_state=valid
    else
      provenance_status=$?
      if [ "$provenance_status" -eq 1 ]; then
        provenance_state=missing
      fi
    fi
    payload_id_state=invalid
    if payload_id="$(manifest_payload_id_value)"; then
      if git_object_id_valid "$payload_id"; then
        payload_id_state=valid
      fi
    else
      payload_id_status=$?
      if [ "$payload_id_status" -eq 1 ]; then
        payload_id_state=missing
      fi
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
  fi
  if [ "$provenance_state" = invalid ]; then
    echo "provenance : invalid @ ${rev:-unknown} (${when:-unknown})"
    status=1
  else
    echo "provenance : ${url:-unknown} @ ${rev:-unknown} (${when:-unknown})"
  fi

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
  if [ "$payload_id_state" = no-manifest ]; then
    echo "published  : unknown (no manifest)"
    [ "$status" -ne 0 ] || status=1
  elif [ "$payload_id_state" = missing ]; then
    echo "published  : unknown (manifest has no payload identity; refresh to add one)"
    [ "$status" -ne 0 ] || status=1
  elif [ "$payload_id_state" = invalid ]; then
    echo "published  : unknown (manifest has invalid payload identity; refresh after inspection)"
    [ "$status" -ne 0 ] || status=1
  elif [ "$provenance_state" = invalid ]; then
    echo "published  : unknown (invalid provenance)"
    [ "$status" -ne 0 ] || status=1
  elif [ "$provenance_state" = valid ] && [ -n "$rev" ]; then
    if head_output="$(provenance_remote_head "$url" 2>/dev/null)"; then
      head="$(printf '%s\n' "$head_output" | LC_ALL=C awk '
        NF == 2 && $2 == "HEAD" { matches++; value = $1; next }
        { invalid = 1 }
        END {
          if (matches != 1 || invalid) exit 1
          print value
        }
      ')" || head=""
    else
      head=""
    fi
    if [ -z "$head_output" ]; then
      echo "published  : unknown (remote unreachable)"
    elif ! git_object_id_valid "$head"; then
      echo "published  : unknown (invalid remote HEAD response)"
    elif ! GIT_NO_LAZY_FETCH=1 git -C "$REPO" \
      cat-file -e "${head}^{commit}" 2>/dev/null; then
      echo "published  : unknown (HEAD $head is not available locally; fetch the source repo and re-run)"
    elif published_payload_id="$(git_managed_payload_id "$REPO" "$head")"; then
      if [ "$published_payload_id" = "$payload_id" ]; then
        echo "published  : current (managed payload matches HEAD $head)"
      else
        echo "published  : STALE — managed payload changed at HEAD $head; re-run vendor.sh to refresh"
        [ "$status" -ne 0 ] || status=1
      fi
    else
      payload_status=$?
      if [ "$payload_status" -eq 2 ]; then
        echo "published  : unknown (HEAD $head has no complete managed payload; inspect the published source layout)"
        [ "$status" -ne 0 ] || status=1
      else
        echo "published  : unknown (managed payload at HEAD $head could not be evaluated locally)"
      fi
    fi
  else
    echo "published  : unknown (manifest has no provenance stamp; refresh to add one)"
    [ "$status" -ne 0 ] || status=1
  fi
  exit "$status"
fi

REV=""
URL=""
PAYLOAD_ID=""

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

# Copy mode distributes committed content only. Under the documented
# non-adversarial inventory threat model, preflight rejects ordinary source
# divergence before stamping committed provenance and payload identity.
# Destination safety is established first; both checks precede mutation.
if [ "$MODE" = "copy" ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  REV="$(git -C "$REPO" rev-parse HEAD)"
  if git_managed_source_pristine "$REPO" "$REV"; then
    :
  else
    source_status=$?
    if [ "$source_status" -eq 2 ]; then
      echo "error: source skills differ from the committed managed payload." >&2
    else
      echo "error: source skills could not be compared with the committed managed payload." >&2
    fi
    echo "Copy mode vendors committed content only; use --link to iterate." >&2
    exit 1
  fi
  if PAYLOAD_ID="$(git_managed_payload_id "$REPO" "$REV")"; then
    :
  else
    payload_status=$?
    if [ "$payload_status" -eq 2 ]; then
      echo "error: committed managed payload is incomplete." >&2
    else
      echo "error: committed managed payload could not be identified." >&2
    fi
    exit 1
  fi
  if source_origin="$(source_origin_value "$REPO")"; then
    if URL="$(canonicalize_source_provenance "$source_origin")"; then
      :
    else
      URL=""
      echo "warning: source provenance was omitted because origin is not an approved GitHub URL." >&2
    fi
  else
    source_origin_status=$?
    URL=""
    if [ "$source_origin_status" -ne 1 ]; then
      echo "warning: source provenance was omitted because origin metadata is invalid." >&2
    fi
  fi
  unset source_origin
fi

mkdir -p .agents/skills
if [ "$MODE" = "link" ]; then
  for s in "${SKILLS[@]}"; do
    dst=".agents/skills/$s"
    rm -rf "$dst"
    ln -sfn "$REPO/skills/$s" "$dst"
  done
  rm -f "$MANIFEST"
else
  vendor_transaction_copy "$REV" "$URL" "$PAYLOAD_ID"
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
