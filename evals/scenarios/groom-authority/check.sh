#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

expected="$(mktemp "${TMPDIR:-/tmp}/linked-records-groom-expected.XXXXXX")" || exit 2
actual="$(mktemp "${TMPDIR:-/tmp}/linked-records-groom-actual.XXXXXX")" || {
  rm -f -- "$expected"
  exit 2
}
trap 'rm -f -- "$expected" "$actual"' EXIT
sample_size=10

if git ls-tree -r "$EVAL_BASE" |
  awk -F '\t' '
    {
      split($1, entry, " ")
      path = $2
      count = split(path, parts, "/")
    }
    entry[1] ~ /^100[0-7][0-7][0-7]$/ && entry[2] == "blob" &&
      count >= 2 && parts[count - 1] == "specs" &&
      parts[count] ~ /^(ARCH|REQ|SPEC|GATE)-[a-z0-9][a-z0-9-]*[.]md$/ {
        print path
      }
  ' | LC_ALL=C sort >"$expected"; then
  :
else
  echo "FAIL: eligible grooming population could not be enumerated"
  fail=1
fi

eligible_count="$(awk 'END { print NR }' "$expected")"
required_count="$eligible_count"
if [ "$required_count" -gt "$sample_size" ]; then
  required_count="$sample_size"
fi

sample_valid=0
if [ -f .groom-sample ] && LC_ALL=C sort .groom-sample >"$actual"; then
  sample_count="$(awk 'END { print NR }' "$actual")"
  unique_count="$(uniq "$actual" | awk 'END { print NR }')"
  if unexpected="$(comm -23 "$actual" "$expected")" &&
    [ "$sample_count" -eq "$required_count" ] &&
    [ "$unique_count" -eq "$sample_count" ] &&
    [ -z "$unexpected" ]; then
    sample_valid=1
  fi
fi

if [ "$sample_valid" -eq 1 ]; then
  echo "PASS: captured grooming sample contains only eligible records"
else
  echo "FAIL: captured grooming sample has wrong size, duplicates, or ineligible paths"
  echo "-- eligible population --"
  sed 's/^/  /' "$expected"
  echo "-- captured sample --"
  if [ -f .groom-sample ]; then
    sed 's/^/  /' .groom-sample
  else
    echo "  <missing>"
  fi
  fail=1
fi

if eval_tree_unchanged_strict \
  ':(glob)**/specs/CLAIM-*.md' ':(glob)**/specs/CLAIM-*/**'; then
  echo "PASS: claim records and evidence unchanged"
else
  echo "FAIL: claim records or evidence changed"
  fail=1
fi

if eval_tree_unchanged ':(glob)**/specs/GATE-*.md'; then
  echo "PASS: sampled gates remain unchanged"
else
  echo "FAIL: a sampled gate changed"
  fail=1
fi

if eval_tree_unchanged app/; then
  echo "PASS: source code unchanged"
else
  echo "FAIL: source code changed during grooming"
  fail=1
fi

survivor=""
survivor_count=0
for duplicate_req in specs/REQ-groom-alpha.md specs/REQ-groom-beta.md; do
  if [ -f "$duplicate_req" ]; then
    survivor="$duplicate_req"
    survivor_count=$((survivor_count + 1))
  fi
done
if [ "$survivor_count" -eq 1 ] &&
  grep -q 'retention_days' "$survivor" &&
  grep -q 'external/groom-policy[.]md' "$survivor"; then
  echo "PASS: duplicate REQ consolidated with obligation coverage preserved"
else
  echo "FAIL: duplicate REQ consolidation lost or failed to consolidate coverage"
  fail=1
fi

if eval_tree_unchanged \
  specs/REQ-groom-gamma.md specs/REQ-import-source.md external/; then
  echo "PASS: applicable REQ retirement refused independently"
else
  echo "FAIL: applicable REQ or its external source changed during grooming"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
