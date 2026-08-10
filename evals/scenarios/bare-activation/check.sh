#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1
if eval_tree_unchanged_strict \
  ':(glob)specs/**' \
  ':(glob)**/specs/**'; then
  echo "PASS: bare activation left all records and claim evidence unchanged"
else
  echo "FAIL: bare activation created, modified, or removed record material"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
