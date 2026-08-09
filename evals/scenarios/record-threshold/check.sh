#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
if eval_tree_unchanged specs/; then
  echo "PASS: no records created or modified for local mechanics"
else
  echo "FAIL: specs/ changed for a plain documentation request:"
  eval_changed_tree specs/ | sed 's/^/  /'
  fail=1
fi
echo "-- changes from eval baseline --"; eval_changed_tree
exit $fail
