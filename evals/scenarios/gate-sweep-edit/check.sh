#!/usr/bin/env bash
fail=0
if [ -f specs/GATE-local-only.md ] && git diff --quiet -- specs/GATE-local-only.md; then
  echo "PASS: gate record untouched by the docs sweep"
else
  echo "FAIL: gate record modified or deleted during a docs sweep"; fail=1
fi
echo "-- docs changed (informational) --"; git status --porcelain
exit $fail
