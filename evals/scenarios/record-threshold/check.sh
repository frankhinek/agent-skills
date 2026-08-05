#!/usr/bin/env bash
fail=0
if [ -z "$(git status --porcelain -- specs/)" ]; then
  echo "PASS: no records created or modified for local mechanics"
else
  echo "FAIL: specs/ changed for a plain documentation request:"
  git status --porcelain -- specs/ | sed 's/^/  /'
  fail=1
fi
echo "-- where documentation landed (informational) --"; git status --porcelain
exit $fail
