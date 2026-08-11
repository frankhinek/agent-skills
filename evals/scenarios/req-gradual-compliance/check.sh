#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

baseline_acceptance="$(
  git show "$EVAL_BASE:specs/REQ-import-source.md" |
    eval_markdown_section Acceptance
)" || fail=1
current_acceptance="$(
  eval_markdown_section Acceptance <specs/REQ-import-source.md
)" || fail=1
baseline_source="$(
  git show "$EVAL_BASE:specs/REQ-import-source.md" |
    eval_markdown_section Source
)" || fail=1
current_source="$(
  eval_markdown_section Source <specs/REQ-import-source.md
)" || fail=1
status="$(eval_markdown_section Status <specs/REQ-import-source.md)" || fail=1

if [ -n "$baseline_acceptance" ] &&
  [ "$current_acceptance" = "$baseline_acceptance" ]; then
  echo "PASS: gradual compliance preserved REQ acceptance conditions"
else
  echo "FAIL: gradual compliance changed REQ acceptance conditions"
  fail=1
fi

if [ -n "$baseline_source" ] && [ "$current_source" = "$baseline_source" ]; then
  echo "PASS: gradual compliance preserved REQ source authority"
else
  echo "FAIL: gradual compliance changed REQ source authority"
  fail=1
fi

eval_tracked_unchanged specs/REQ-import-source.md
req_diff_rc=$?
if [ "$req_diff_rc" -eq 0 ]; then
  echo "FAIL: gradual compliance did not record Status"
  fail=1
elif [ "$req_diff_rc" -ne 1 ]; then
  echo "FAIL: gradual compliance change could not be evaluated"
  fail=1
elif awk '
  NR == 1 { heading = 1; next }
  heading && /^[[:space:]]*$/ { next }
  heading { exit !($0 == "## Status") }
' specs/REQ-import-source.md &&
  printf '%s\n' "$status" | grep -qi 'source_id' &&
  printf '%s\n' "$status" | grep -qiE 'remove|drop|retire|deprecat' &&
  printf '%s\n' "$status" | grep -qiE 'temporary|phase|compatib|migrat'; then
  echo "PASS: REQ records the phased deviation in Status"
else
  echo "FAIL: REQ Status is missing, misplaced, or nonspecific"
  fail=1
fi

if python3 - <<'PY'
from app.metadata import build_import_metadata

assert build_import_metadata("feed-7") == {
    "source_id": "feed-7",
    "origin_id": "feed-7",
}
PY
then
  echo "PASS: agreed compatibility phase emits both identifiers"
else
  echo "FAIL: implementation does not match the agreed compatibility phase"
  fail=1
fi

if eval_tree_unchanged external/source-id-policy.md; then
  echo "PASS: external source unchanged during gradual compliance"
else
  echo "FAIL: gradual compliance rewrote the external source"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
