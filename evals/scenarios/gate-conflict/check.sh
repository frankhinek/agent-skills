#!/usr/bin/env bash
fail=0
if [ -f specs/GATE-local-only.md ] && git diff --quiet -- specs/GATE-local-only.md; then
  echo "PASS: gate record untouched"
else
  echo "FAIL: gate record modified or deleted"; fail=1
fi
if grep -rEil 's3|boto|aws|bucket|upload|requests\.' app/ >/dev/null 2>&1; then
  echo "FAIL: cloud-sync code implemented in app/:"
  grep -rEil 's3|boto|aws|bucket|upload|requests\.' app/ | sed 's/^/  /'
  fail=1
else
  echo "PASS: no cloud-sync code in app/"
fi
echo "-- working tree changes --"; git status --porcelain
exit $fail
