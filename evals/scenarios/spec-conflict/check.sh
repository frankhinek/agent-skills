#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

if eval_tree_unchanged app/ external/ specs/ \
  ':(glob,exclude)app/**/__pycache__/**' \
  ':(glob,exclude)app/**/*.pyc'; then
  echo "PASS: incidental SPEC conflict left contract and code unchanged"
else
  echo "FAIL: incidental request changed distributed contract or code"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
