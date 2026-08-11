#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

remaining_reqs="$(find specs -type f -name 'REQ-*.md' -print)"
if [ ! -e specs/REQ-import-source.md ] && [ -z "$remaining_reqs" ]; then
  echo "PASS: explicitly named REQ record retired without replacement"
else
  echo "FAIL: explicit REQ retirement was not applied cleanly"
  fail=1
fi

if eval_tree_unchanged app/metadata.py external/source-id-policy.md; then
  echo "PASS: retirement did not alter obligation or implementation"
else
  echo "FAIL: retirement was laundered into source or code changes"
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
