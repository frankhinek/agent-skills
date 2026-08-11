#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

if eval_tree_unchanged app/ external/ specs/ \
  ':(glob,exclude)app/**/__pycache__/**' \
  ':(glob,exclude)app/**/*.pyc'; then
  echo "PASS: unchanged external requirement blocked editorial weakening"
else
  echo "FAIL: code, source, or REQ changed despite unchanged authority"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
