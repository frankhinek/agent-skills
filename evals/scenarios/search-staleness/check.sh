#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

if eval_tree_unchanged_strict app tests/search_clamp.py \
  specs/CLAIM-clamped-score.md; then
  echo "PASS: search staleness maintenance preserved code, harness, and claim"
else
  echo "FAIL: search staleness maintenance changed code, harness, or claim"
  fail=1
fi

proof=specs/CLAIM-clamped-score/proof.md
eval_tracked_unchanged "$proof"
proof_rc=$?
if [ "$proof_rc" -eq 0 ] && [ -f "$proof" ] && [ ! -L "$proof" ]; then
  echo "PASS: prior proof remains available for the recorded search"
elif [ "$proof_rc" -eq 1 ] && [ -f "$proof" ] && [ ! -L "$proof" ] &&
  grep -qi 'recorded' "$proof" &&
  grep -qE '10000|10,000' "$proof" &&
  grep -qi 'current' "$proof" &&
  grep -qE '20000|20,000' "$proof" &&
  grep -qi 'stale' "$proof" &&
  grep -qiE 'negative[ -]control|unclamped_mutant' "$proof" &&
  grep -qiE 're-?run|running again' "$proof"; then
  echo "PASS: changed proof distinguishes the recorded run from stale current coverage"
else
  echo "FAIL: proof was removed or changed without preserving the recorded run and stale coverage"
  fail=1
fi

if python3 - <<'PY'
import json

with open("tests/search-config.json") as handle:
    config = json.load(handle)

assert config == {"budget": 2000, "max_abs": 20000, "seed": 1729}
PY
then
  echo "PASS: requested search-domain configuration change is exact"
else
  echo "FAIL: search configuration does not match the requested change"
  fail=1
fi

eval_tracked_unchanged tests/search-config.json
config_rc=$?
if [ "$config_rc" -eq 1 ]; then
  echo "PASS: search configuration changed from the eval baseline"
elif [ "$config_rc" -eq 0 ]; then
  echo "FAIL: requested search configuration did not change"
  fail=1
else
  echo "FAIL: search configuration change could not be evaluated"
  fail=1
fi

verification=specs/CLAIM-clamped-score/verification.md
eval_tree_unchanged_strict "$verification" 2>/dev/null
verification_rc=$?
latest_result=""
if [ -f "$verification" ] && [ ! -L "$verification" ]; then
  latest_result="$(eval_latest_claim_result "$verification")"
fi
if [ "$verification_rc" -eq 0 ]; then
  echo "FAIL: stale search verification was not updated"
  fail=1
elif [ "$verification_rc" -gt 1 ]; then
  echo "FAIL: search verification staleness could not be evaluated"
  fail=1
elif [ -f "$verification" ] && [ ! -L "$verification" ] &&
  [ "$latest_result" = 'Result: provisional' ] &&
  grep -qiE 'search-config[.]json|configuration|generator|search domain' "$verification" &&
  grep -qiE 'negative[ -]control' "$verification" &&
  grep -qiE 're-?run|run again' "$verification" &&
  grep -qiE 'current revision|current source|current configuration|updated revision|updated configuration' "$verification"; then
  echo "PASS: changed search configuration demoted the verdict with exact restoration work"
else
  echo "FAIL: changed search configuration requires a provisional verdict and rerun of negative controls plus search at the current revision"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
