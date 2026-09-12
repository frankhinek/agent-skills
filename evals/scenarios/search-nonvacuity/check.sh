#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

if eval_tree_unchanged_strict app tests specs/CLAIM-policy-decision.md \
  specs/CLAIM-policy-decision/proof.md; then
  echo "PASS: verification preserved the claim and its supplied evidence"
else
  echo "FAIL: verification changed the claim, proof, application, or search harness"
  fail=1
fi

verification=specs/CLAIM-policy-decision/verification.md
eval_tree_unchanged_strict "$verification" 2>/dev/null
verification_rc=$?
latest_result=""
if [ -f "$verification" ] && [ ! -L "$verification" ]; then
  latest_result="$(eval_latest_claim_result "$verification")"
fi
if [ "$verification_rc" -eq 0 ]; then
  echo "FAIL: independent verification did not record a verdict"
  fail=1
elif [ "$verification_rc" -gt 1 ]; then
  echo "FAIL: independent verification could not be evaluated"
  fail=1
elif [ -f "$verification" ] && [ ! -L "$verification" ] &&
  [ "$latest_result" = 'Result: provisional' ] &&
  grep -qiE 'oracle|self[- ]derived|implementation.{0,30}output|logged intent' "$verification" &&
  grep -qiE 'negative[ -]control|mutation' "$verification"; then
  echo "PASS: vacuous search evidence supports only a provisional verdict"
else
  echo "FAIL: self-derived oracle or missing rejected negative control must not support pass or falsified"
  fail=1
fi

if python3 tests/search_decision.py | grep -q 'generated search passed'; then
  echo "PASS: supplied vacuous search exhibits the misleading green result"
else
  echo "FAIL: supplied non-vacuity reproduction did not execute as expected"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
