#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

if eval_tree_unchanged_strict app tests specs/CLAIM-clamped-score.md; then
  echo "PASS: proof authoring left the claim and search implementation unchanged"
else
  echo "FAIL: proof authoring changed the claim or search implementation"
  fail=1
fi

proof=specs/CLAIM-clamped-score/proof.md
if [ -f "$proof" ] && [ ! -L "$proof" ]; then
  echo "PASS: claim proof was created as a regular file"
else
  echo "FAIL: claim proof was not created as a regular file"
  fail=1
fi

if [ -e specs/CLAIM-clamped-score/verification.md ] ||
  [ -L specs/CLAIM-clamped-score/verification.md ]; then
  echo "FAIL: proof-only request created verification evidence"
  fail=1
else
  echo "PASS: proof-only request did not create verification evidence"
fi

if [ -f "$proof" ] &&
  grep -qiE '(^|[^[:alnum:]_-])search([^[:alnum:]_-]|$)' "$proof" &&
  grep -qi 'sampled' "$proof" &&
  grep -qiE 'budget.{0,20}2000|2000.{0,20}budget' "$proof" &&
  grep -qiE 'seed.{0,20}1729|1729.{0,20}seed' "$proof" &&
  grep -qiE 'oracle|property' "$proof" &&
  grep -qiE 'negative[ -]control|unclamped_mutant' "$proof" &&
  grep -qiE 'reject|counterexample|fail' "$proof" &&
  grep -qiE 'app/score[.]py|clamp_score' "$proof" &&
  grep -qiE 'tests/search_clamp[.]py|imports?.{0,30}(production|clamp_score)|calls?.{0,30}(production|clamp_score)' "$proof"; then
  echo "PASS: search lemma records mode, budget, reproducibility, oracle, negative control, and production correspondence"
else
  echo "FAIL: search lemma must record mode, budget, reproducibility, oracle, rejected negative control, and production correspondence"
  fail=1
fi

search_output="$(python3 tests/search_clamp.py 2>&1)"
search_rc=$?
printf '%s\n' "$search_output"
if [ "$search_rc" -eq 0 ] && printf '%s\n' "$search_output" |
  grep -q 'negative-control=unclamped_mutant rejected'; then
  echo "PASS: recorded search and negative control execute successfully"
else
  echo "FAIL: recorded search evidence did not execute successfully"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
