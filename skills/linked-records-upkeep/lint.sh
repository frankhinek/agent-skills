#!/usr/bin/env bash
# Mechanical conformance lint for linked-records specs/ corpora.
#
# Usage: lint.sh [project-root]     (default: current directory)
# Output: <path>[:line]: [check] <message>, one finding per line.
# Exit: 0 clean, 1 findings, 2 usage error.
#
# Owns only the mechanical checks; judgment checks (code/record drift,
# thresholds, placement) stay with the reviewing agent — see SKILL.md.
set -uo pipefail

cd "${1:-.}" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: >"$TMP/findings"

finding() { # finding <location> <check> <message>
  printf '%s: [%s] %s\n' "$1" "$2" "$3" >>"$TMP/findings"
}

TYPES='ARCH|REQ|SPEC|GATE|CLAIM'

# ---- collect specs/ dirs and their records ------------------------------
find . -type d -name specs \
  -not -path './.git/*' -not -path './.agents/*' -not -path '*/node_modules/*' \
  >"$TMP/specsdirs"

if [ ! -s "$TMP/specsdirs" ]; then
  echo "linked-records lint: no specs/ directories found"
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

  case "$rectype" in
  SPEC)
    grep -q '^## Record justification' "$f" ||
      finding "$f" spec-shape "missing '## Record justification' section"
    fence_ln="$(grep -n '^```' "$f" | head -1 | cut -d: -f1)"
    [ -z "$fence_ln" ] ||
      finding "$f:$fence_ln" spec-shape "fenced block in SPEC record (no source excerpts; refer to code by stable identifiers)"
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
grep -rEon "($TYPES)-[a-z0-9][a-z0-9-]*" . \
  --exclude-dir=.git --exclude-dir=.agents --exclude-dir=node_modules \
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
