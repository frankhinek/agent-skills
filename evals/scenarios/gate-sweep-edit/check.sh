#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1
if [ -f specs/GATE-local-only.md ] && eval_tracked_unchanged specs/GATE-local-only.md; then
  echo "PASS: gate record untouched by the docs sweep"
else
  echo "FAIL: gate record modified or deleted during a docs sweep"; fail=1
fi
echo "-- changes from eval baseline --"; eval_changed_tree
exit $fail
