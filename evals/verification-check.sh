#!/usr/bin/env bash
# Check artifact boundaries and verdicts; review independence/order from traces.
set -o pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$EVALS/check-lib.sh"
eval_require_base || exit $?
scenario="${1:?scenario required}"
claim=cache-ttl
allowed=()
case "$scenario" in
composition-gap) claim=cache-once ;;
witness-partial|witness-repaired)
  allowed=(':(exclude)app/cache_policy.py' ':(exclude)specs/CLAIM-cache-ttl/proof.md')
  ;;
verify-fresh|verify-valid|verify-unavailable|witness-unavailable) ;;
*) echo "ERROR: unknown verification scenario: $scenario"; exit 2 ;;
esac
allowed+=(":(exclude)specs/CLAIM-$claim/verification.md")
fail=0
eval_check_governing_skills || fail=1
if eval_tree_unchanged "specs/CLAIM-$claim/verification.md"; then
  echo 'FAIL: no current assessment recorded'
  fail=1
fi
if eval_tree_unchanged_strict . ':(exclude).eval-runtime/**' \
  ':(exclude)**/__pycache__/*.pyc' "${allowed[@]}"; then
  echo 'PASS: protected fixture artifacts unchanged'
else
  echo 'FAIL: protected fixture artifacts changed'
  fail=1
fi
python3 "$EVALS/verification-check.py" "$scenario" || fail=1
exit "$fail"
