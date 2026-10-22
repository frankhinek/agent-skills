#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1
for path in packages/publisher/payload.py \
  packages/publisher/specs/ARCH-publisher.md packages/reader/render.py \
  packages/reader/specs/SPEC-published-record.md; do
  if [ ! -f "$path" ] || [ -L "$path" ]; then
    echo "FAIL: discovery fixture is incomplete: $path"
    fail=1
  fi
done

if eval_tree_unchanged app/ external/ specs/ packages/ \
  ':(glob,exclude)**/__pycache__/**' ':(glob,exclude)**/*.pyc'; then
  echo "PASS: consumer contract left both packages and records unchanged"
else
  echo "FAIL: local request changed the consumer contract or governed code"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit "$fail"
