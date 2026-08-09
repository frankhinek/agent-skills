#!/usr/bin/env bash
# Mechanical conformance lint for linked-records specs/ corpora.
#
# Usage: lint.sh [project-root]     (default: current directory)
# Output: <path>[:line]: [check] <message>, one finding per line.
# Exit: 0 clean, 1 findings, 2 invocation/setup error.
#
# Owns only the mechanical checks; judgment checks (code/record drift,
# thresholds, placement) stay with the reviewing agent — see SKILL.md.
set -uo pipefail

cd "${1:-.}" || exit 2

setup_error() {
  printf 'linked-records lint: [setup] %s\n' "$1" >&2
  exit 2
}

ROOT="$(pwd -P)" || setup_error "unable to resolve project root"
TMP_PARENT="${TMPDIR:-/tmp}"
TMP_PARENT="$(CDPATH= cd -- "$TMP_PARENT" 2>/dev/null && pwd -P)" ||
  setup_error "unable to resolve temporary directory: ${TMPDIR:-/tmp}"
TMP_PREFIX="${TMP_PARENT%/}/linked-records-lint."

if ! TMP_RAW="$(mktemp -d "${TMP_PREFIX}XXXXXX")" || [ -z "$TMP_RAW" ]; then
  setup_error "unable to create scratch directory"
fi
if ! TMP="$(CDPATH= cd -- "$TMP_RAW" 2>/dev/null && pwd -P)"; then
  setup_error "unsafe scratch directory returned by mktemp: $TMP_RAW"
fi

scratch_path_is_safe() {
  local path="${1:-}"
  local suffix
  case "$path" in
  "$TMP_PREFIX"?*)
    suffix="${path#"$TMP_PREFIX"}"
    case "$suffix" in
    */*) return 1 ;;
    *) return 0 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

scratch_path_is_safe "$TMP" ||
  setup_error "unsafe scratch directory returned by mktemp: $TMP_RAW"

trap 'rm -rf -- "$TMP"' EXIT

if ! : >"$TMP/findings"; then
  setup_error "unable to initialize scratch directory"
fi

finding() { # finding <location> <check> <message>
  printf '%s: [%s] %s\n' "$1" "$2" "$3" >>"$TMP/findings"
}

TYPES='ARCH|REQ|SPEC|GATE|CLAIM'

# ---- collect specs/ dirs and their records ------------------------------
find . -type d -name specs \
  -not -path './.git/*' -not -path './.agents/*' -not -path '*/node_modules/*' \
  >"$TMP/specsdirs"

if [ ! -s "$TMP/specsdirs" ]; then
  printf 'linked-records lint: no specs/ directories found under %s\n' "$ROOT"
  exit 0
fi

: >"$TMP/records"
while IFS= read -r d; do
  find "$d" -maxdepth 1 -type f -name '*.md' >>"$TMP/records"
done <"$TMP/specsdirs"
sort -o "$TMP/records" "$TMP/records"

sed 's#.*/##; s#\.md$##' "$TMP/records" | sort >"$TMP/stems"
uniq "$TMP/stems" >"$TMP/stems.u"

# ---- repository-unique record IDs ---------------------------------------
uniq -d "$TMP/stems" | while IFS= read -r dup; do
  paths="$(grep "/$dup\.md\$" "$TMP/records" | tr '\n' ' ')"
  finding "$dup" unique-id "record ID in multiple specs dirs: $paths"
done

# ---- per-record checks --------------------------------------------------
while IFS= read -r f; do
  base="${f##*/}"
  stem="${base%.md}"
  rectype="${stem%%-*}"

  case "$base" in
  index.md | INDEX.md | README.md | readme.md)
    finding "$f" no-index "index-like file in specs/ (records need no index)"
    continue
    ;;
  esac

  if ! printf '%s' "$stem" | grep -Eq "^($TYPES)-[a-z0-9][a-z0-9-]*\$"; then
    finding "$f" type "not a recognized record name: want <TYPE>-<kebab-slug>.md, TYPE one of ARCH/REQ/SPEC/GATE/CLAIM"
    continue
  fi

  first="$(grep -m1 -v '^[[:space:]]*$' "$f" || true)"
  case "$first" in
  "# $stem: "?*) : ;;
  *) finding "$f" heading "first line must be '# $stem: <title>' (found: ${first:-empty file})" ;;
  esac

  # relative markdown links resolve
  dir="${f%/*}"
  grep -n -o '\]([^)]*)' "$f" 2>/dev/null | sed 's/](\(.*\))/\1/' |
    while IFS=: read -r ln target; do
      case "$target" in
      http://* | https://* | mailto:* | "#"* | "") continue ;;
      esac
      target="${target%%#*}"
      [ -n "$target" ] || continue
      [ -e "$dir/$target" ] || finding "$f:$ln" link "broken relative link: $target"
    done

  tombstone_ln="$(awk '
    {
      line = tolower($0)
      gsub(/\*\*|__/, "", line)
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      if (line ~ /^tombstone[[:space:]]*:/ ||
          line ~ /^status[[:space:]]*:[[:space:]]*(tombstone|retired|deprecated|superseded)([[:space:][:punct:]]|$)/ ||
          line ~ /^##[[:space:]]+(tombstone|retired|deprecated|superseded)[[:space:]]*$/) {
        print NR
        exit
      }
    }
  ' "$f")"
  [ -z "$tombstone_ln" ] ||
    finding "$f:$tombstone_ln" tombstone "explicit tombstone marker; delete superseded records instead"

  case "$rectype" in
  SPEC)
    justification_count="$(grep -Ec '^## Record justification[[:space:]]*$' "$f" || true)"
    if [ "$justification_count" -eq 0 ]; then
      finding "$f" spec-shape "missing '## Record justification' section"
    elif [ "$justification_count" -gt 1 ]; then
      finding "$f" spec-shape "must contain exactly one '## Record justification' section"
    else
      justification_nonempty="$(awk '
        /^## Record justification[[:space:]]*$/ { in_section = 1; next }
        /^##[[:space:]]/ { in_section = 0 }
        in_section && /[^[:space:]]/ { found = 1 }
        END { print found + 0 }
      ' "$f")"
      [ "$justification_nonempty" -eq 1 ] ||
        finding "$f" spec-shape "'## Record justification' section must contain non-empty content"
    fi

    awk '
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        marker = substr(line, 1, 1)
        if (marker != "`" && marker != "~")
          next

        width = 0
        while (substr(line, width + 1, 1) == marker)
          width++
        if (width < 3)
          next

        label = substr(line, width + 1)
        sub(/^[[:space:]]*/, "", label)
        sub(/[[:space:]]*$/, "", label)

        if (in_fence) {
          if (marker == fence_marker && width >= fence_width && label == "")
            in_fence = 0
          next
        }

        in_fence = 1
        fence_marker = marker
        fence_width = width
        if (label != "text" && label != "mermaid" &&
            label != "plantuml" && label != "dot")
          print NR
      }
    ' "$f" | while IFS= read -r fence_ln; do
      finding "$f:$fence_ln" spec-shape "fenced block must use an approved diagram label: text, mermaid, plantuml, or dot"
    done
    ;;
  GATE)
    gate_ln="$(grep -En '^## Gate[[:space:]]*$' "$f" | head -1 | cut -d: -f1)"
    just_ln="$(grep -En '^## Justification[[:space:]]*$' "$f" | head -1 | cut -d: -f1)"
    [ -n "$gate_ln" ] || finding "$f" gate-shape "missing '## Gate' section"
    [ -n "$just_ln" ] || finding "$f" gate-shape "missing '## Justification' section"
    if [ -n "$gate_ln" ] && [ -n "$just_ln" ] && [ "$gate_ln" -gt "$just_ln" ]; then
      finding "$f" gate-shape "'## Gate' must precede '## Justification'"
    fi
    first_h2="$(grep -m1 '^## ' "$f" | sed 's/[[:space:]]*$//')"
    if [ -n "$first_h2" ] && [ "$first_h2" != "## Gate" ]; then
      finding "$f" gate-shape "substantive content must start with '## Gate' (found '$first_h2')"
    fi
    status_ln="$(grep -n '^## Status' "$f" | head -1 | cut -d: -f1)"
    [ -z "$status_ln" ] ||
      finding "$f:$status_ln" gate-shape "'## Status' is not allowed on GATE records"
    ;;
  CLAIM)
    h2_ln="$(grep -n '^## ' "$f" | head -1 | cut -d: -f1)"
    [ -z "$h2_ln" ] ||
      finding "$f:$h2_ln" claim-shape "CLAIM records hold only the property statement; evidence belongs in $stem/"
    claim_metadata_ln="$(awk '
      {
        line = tolower($0)
        gsub(/\*\*|__/, "", line)
        sub(/^[[:space:]]*/, "", line)
        if (line ~ /^(proof|verdict)[[:space:]]*:/) {
          print NR
          exit
        }
      }
    ' "$f")"
    [ -z "$claim_metadata_ln" ] ||
      finding "$f:$claim_metadata_ln" claim-shape "claim-level proof/verdict material belongs in $stem/ evidence"
    ;;
  esac
done <"$TMP/records"

# ---- directories inside specs/: only CLAIM evidence dirs ----------------
while IFS= read -r d; do
  find "$d" -maxdepth 1 -type d ! -path "$d" | while IFS= read -r sub; do
    name="${sub##*/}"
    case "$name" in
    CLAIM-*)
      [ -f "$d/$name.md" ] ||
        finding "$sub" orphan-evidence "evidence directory without a $name.md record"
      find "$sub" -type f ! -name proof.md ! -name verification.md |
        while IFS= read -r extra; do
          finding "$extra" evidence-shape "unexpected evidence file (expected proof.md / verification.md)"
        done
      ;;
    *)
      finding "$sub" stray-dir "unexpected directory in specs/ (only CLAIM-<slug>/ evidence dirs belong here)"
      ;;
    esac
  done
done <"$TMP/specsdirs"

# ---- references to nonexistent records ----------------------------------
# Search regular text files while pruning conventional generated, dependency,
# and environment trees; -I makes binary handling explicit on both BSD and
# GNU grep.
reference_prune=(
  -name .git -o -name .agents -o -name node_modules -o
  -name build -o -name dist -o -name .venv -o -name venv -o
  -name vendor
)

# A nested SKILL.md marks agent instructions, not project source. Preserve a
# root SKILL.md so a project that is itself a skill cannot suppress its scan.
find . \
  \( -type d \( "${reference_prune[@]}" \) -prune \) -o \
  -type f -name SKILL.md -print \
  2>/dev/null | sort -u >"$TMP/skillroots" || true
while IFS= read -r skill_file; do
  skill_dir="${skill_file%/SKILL.md}"
  [ "$skill_dir" = . ] && continue
  skill_pattern="$(printf '%s\n' "$skill_dir" | sed 's/[][\\*?]/\\&/g')"
  reference_prune+=( -o -path "$skill_pattern" )
done <"$TMP/skillroots"

find . \
  \( -type d \( "${reference_prune[@]}" \) -prune \) -o \
  -type f -exec grep -IHoEn "($TYPES)-[a-z0-9][a-z0-9-]*" -- {} + \
  2>/dev/null | sort -u >"$TMP/refs" || true
while IFS=: read -r p ln id; do
  grep -qx "$id" "$TMP/stems.u" ||
    finding "$p:$ln" dangling-ref "references non-existent record $id"
done <"$TMP/refs"

# ---- report -------------------------------------------------------------
if [ -s "$TMP/findings" ]; then
  sort -u "$TMP/findings"
  echo "linked-records lint: $(sort -u "$TMP/findings" | grep -c .) finding(s)"
  exit 1
fi
echo "linked-records lint: clean ($(grep -c . "$TMP/records") records)"
exit 0
