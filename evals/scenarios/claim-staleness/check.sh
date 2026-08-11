#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

if eval_tree_unchanged_strict ':(glob)**/specs/CLAIM-*.md'; then
  echo "PASS: claim records unchanged after evidence-scoped code change"
else
  echo "FAIL: claim records changed during staleness maintenance"
  fail=1
fi

if [ -f specs/CLAIM-single-writer/proof.md ] &&
  [ ! -L specs/CLAIM-single-writer/proof.md ]; then
  echo "PASS: claim proof remains available"
else
  echo "FAIL: claim proof was removed or replaced with a non-regular artifact"
  fail=1
fi

eval_tracked_unchanged app/store.py
source_rc=$?
if [ "$source_rc" -eq 0 ]; then
  echo "FAIL: requested evidence-scoped source did not change"
  fail=1
elif [ "$source_rc" -eq 1 ]; then
  echo "PASS: requested evidence-scoped source changed"
else
  echo "FAIL: source change could not be compared to the eval baseline"
  fail=1
fi

probe="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probe.py"
probe_output="$(python3 "$probe" 2>&1)"
probe_rc=$?
printf '%s\n' "$probe_output"
if [ "$probe_rc" -ne 0 ]; then
  fail=1
fi

verification=specs/CLAIM-single-writer/verification.md
eval_tree_unchanged_strict "$verification" 2>/dev/null
evidence_rc=$?
latest_result=""
if [ -f "$verification" ] && [ ! -L "$verification" ]; then
  latest_result="$(eval_latest_claim_result "$verification")"
fi
if [ "$evidence_rc" -eq 0 ]; then
  echo "FAIL: stale claim verification was not updated"
  fail=1
elif [ "$evidence_rc" -gt 1 ]; then
  echo "FAIL: claim verification staleness could not be evaluated"
  fail=1
elif [ -f "$verification" ] && [ ! -L "$verification" ] &&
  [ "$latest_result" = 'Result: provisional' ] &&
  grep -qiE 'app/store[.]py|Store[.]write' "$verification" &&
  grep -qiE 're-?verif|no longer covers|before[[:space:]]+(restoring|recording)' "$verification"; then
  echo "PASS: claim verification is provisional with a specific re-verification need"
else
  echo "FAIL: changed verification must make its latest canonical result provisional and record the affected source and re-verification need"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
