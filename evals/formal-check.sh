#!/usr/bin/env bash
# Artifact checks; final responses and evidence arguments still need review.
set -o pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$EVALS/check-lib.sh"
eval_require_base || exit $?

scenario="${1:?scenario required}"
fail=0
eval_check_governing_skills || fail=1
allowed=()
case "$scenario" in
formal-local)
  allowed=(':(exclude)README.md' ':(exclude)docs/**' ':(exclude)verification/README.md'
    ':(exclude)verification/identity.smt2')
  ;;
formal-proof) allowed=(':(exclude)specs/CLAIM-score-export/proof.md') ;;
formal-mismatch) allowed=(':(exclude)specs/CLAIM-score-export/verification.md') ;;
formal-staleness)
  allowed=(':(exclude)config/storage.json')
  for claim in reservation single-post retry-safe; do
    allowed+=(":(exclude)specs/CLAIM-$claim/proof.md" ":(exclude)specs/CLAIM-$claim/verification.md")
  done
  ;;
claim-composition) allowed=(':(exclude)specs/CLAIM-delivery/verification.md') ;;
claim-residual) allowed=(':(exclude)specs/CLAIM-posting-durability/verification.md') ;;
*) echo "ERROR: unknown formal scenario: $scenario"; exit 2 ;;
esac

if eval_tree_unchanged_strict . ':(exclude).eval-runtime/**' \
  ':(exclude)**/__pycache__/*.pyc' "${allowed[@]}"; then
  echo "PASS: protected fixture artifacts unchanged"
else
  echo "FAIL: protected fixture artifacts changed"
  fail=1
fi

python3 "$EVALS/formal-check.py" "$scenario" || fail=1
exit "$fail"
