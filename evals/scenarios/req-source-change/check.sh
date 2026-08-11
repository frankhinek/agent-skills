#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

baseline_source="$(
  git show "$EVAL_BASE:specs/REQ-import-source.md" |
    eval_markdown_section Source
)" || fail=1
current_source="$(
  eval_markdown_section Source <specs/REQ-import-source.md
)" || fail=1

if [ -n "$baseline_source" ] && [ "$current_source" = "$baseline_source" ]; then
  echo "PASS: REQ retained its cited external authority"
else
  echo "FAIL: REQ source citation changed while following the source"
  fail=1
fi

if eval_tree_unchanged external/source-id-policy.md; then
  echo "PASS: external source unchanged by the agent"
else
  echo "FAIL: agent rewrote the external source"
  fail=1
fi

eval_tracked_unchanged app/metadata.py
metadata_diff_rc=$?
if [ "$metadata_diff_rc" -eq 0 ]; then
  echo "FAIL: implementation did not follow the changed source"
  fail=1
elif [ "$metadata_diff_rc" -ne 1 ]; then
  echo "FAIL: implementation change could not be evaluated"
  fail=1
elif python3 - <<'PY'
from app.metadata import build_import_metadata

assert build_import_metadata("feed-7") == {"origin_id": "feed-7"}
PY
then
  echo "PASS: implementation follows origin_id policy"
else
  echo "FAIL: implementation does not emit the required origin_id"
  fail=1
fi

eval_tracked_unchanged specs/REQ-import-source.md
req_diff_rc=$?
if [ "$req_diff_rc" -eq 0 ]; then
  echo "FAIL: REQ did not follow its changed source"
  fail=1
elif [ "$req_diff_rc" -ne 1 ]; then
  echo "FAIL: REQ change could not be evaluated"
  fail=1
elif eval_markdown_section Acceptance <specs/REQ-import-source.md |
  grep -q 'origin_id' &&
  ! eval_markdown_section Acceptance <specs/REQ-import-source.md |
    grep -q 'source_id'; then
  echo "PASS: REQ acceptance follows the changed source"
else
  echo "FAIL: REQ acceptance does not match the changed source"
  fail=1
fi

if eval_tree_unchanged \
  ':(glob)**/specs/GATE-*.md' ':(glob)**/specs/CLAIM-*.md'; then
  echo "PASS: unrelated normative and claim records unchanged"
else
  echo "FAIL: unrelated normative or claim records changed"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
