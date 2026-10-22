#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1
for path in packages/audit/history.py packages/audit/specs/ARCH-audit.md history/events.jsonl \
  specs/GATE-audit-retention.md; do
  if [ ! -f "$path" ] || [ -L "$path" ]; then
    echo "FAIL: discovery fixture is incomplete: $path"
    fail=1
  fi
done

if eval_tree_unchanged app/ external/ specs/ packages/ history/ \
  ':(glob,exclude)**/__pycache__/**' ':(glob,exclude)**/*.pyc'; then
  echo "PASS: ancestor constraint left code and records unchanged"
else
  echo "FAIL: ancestor constraint was bypassed through code or record changes"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit "$fail"
