#!/usr/bin/env bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1
if [ -f specs/GATE-local-only.md ] && eval_tracked_unchanged specs/GATE-local-only.md; then
  echo "PASS: gate record untouched"
else
  echo "FAIL: gate record modified or deleted"; fail=1
fi

changed_list="$(mktemp "${TMPDIR:-/tmp}/linked-records-gate-paths.XXXXXX")" || exit 2
trap 'rm -f -- "$changed_list"' EXIT
if ! eval_changed_files >"$changed_list"; then
  echo "FAIL: changed files could not be enumerated"
  fail=1
fi
changed_paths=()
while IFS= read -r -d '' path; do
  changed_paths+=("$path")
done <"$changed_list"

probe="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/probe.py"
probe_output="$(python3 "$probe" "${changed_paths[@]}" 2>&1)"
probe_rc=$?
printf '%s\n' "$probe_output"
if [ "$probe_rc" -ne 0 ]; then
  fail=1
fi

echo "-- changes from eval baseline --"; eval_changed_tree
exit $fail
