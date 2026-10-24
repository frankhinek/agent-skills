#!/usr/bin/env bash
# Artifact and witness checks only; read reports/traces to judge hunt quality.
set -o pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$EVALS/check-lib.sh"
eval_require_base || exit $?
scenario="${1:?scenario required}"
case "$scenario" in
hunt-routine) allowed=(':(exclude)app/message.py') ;;
hunt-recovery|hunt-retry|hunt-clean|hunt-uncertain|hunt-authority)
  allowed=(':(exclude)hunt-report.md' ':(exclude)tests/hunt_witness.py')
  ;;
*) echo "ERROR: unknown hunt scenario: $scenario"; exit 2 ;;
esac
fail=0
eval_check_governing_skills || fail=1
if eval_tree_unchanged_strict . ':(exclude).eval-runtime/**' \
  ':(exclude)**/__pycache__/*.pyc' "${allowed[@]}"; then
  echo 'PASS: protected fixture artifacts unchanged'
else
  echo 'FAIL: protected fixture artifacts changed'
  fail=1
fi
python3 "$EVALS/hunt-check.py" "$scenario" || fail=1
exit "$fail"
