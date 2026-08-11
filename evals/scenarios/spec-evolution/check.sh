#!/usr/bin/env bash
set -o pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/check-lib.sh"
eval_require_base || exit $?

fail=0
eval_check_governing_skills || fail=1

changed_paths="$(eval_tracked_changed_files \
  app/handler.py app/exporter.py specs/SPEC-note-payload.md)"
changed_paths_rc=$?
if [ "$changed_paths_rc" -ne 0 ]; then
  echo "FAIL: requested evolution changes could not be evaluated"
  fail=1
else
  for changed_path in app/handler.py app/exporter.py specs/SPEC-note-payload.md; do
    if printf '%s\n' "$changed_paths" | grep -Fxq "$changed_path"; then
      echo "PASS: requested evolution changed $changed_path"
    else
      echo "FAIL: requested evolution left $changed_path unchanged"
      fail=1
    fi
  done
fi

if python3 - <<'PY'
from app import exporter, handler

writes = []


def capture(_store, key, value):
    writes.append((key, value))


handler.store.write = capture.__get__(handler.store, type(handler.store))
handler.save_note("n1", "hello")
assert writes == [("note-n1", {"body": "hello"})]


class Reader:
    def read(self, key):
        assert key == "note-n1"
        return {"body": "hello"}


exporter.store = Reader()
assert exporter.export_note("n1") == "hello"
PY
then
  echo "PASS: distributed implementation uses body consistently"
else
  echo "FAIL: distributed implementation does not use body consistently"
  fail=1
fi

if grep -q '`body`' specs/SPEC-note-payload.md &&
  ! grep -q '`text`' specs/SPEC-note-payload.md &&
  grep -q '^## Record justification[[:space:]]*$' specs/SPEC-note-payload.md; then
  echo "PASS: SPEC describes the requested distributed end state"
else
  echo "FAIL: SPEC does not describe the body-key end state"
  fail=1
fi

if eval_tree_unchanged \
  app/store.py external/ ':(glob)**/specs/REQ-*.md' \
  ':(glob)**/specs/GATE-*.md' ':(glob)**/specs/CLAIM-*.md'; then
  echo "PASS: unrelated authority sources unchanged"
else
  echo "FAIL: unrelated authority source changed"
  fail=1
fi

echo "-- changes from eval baseline --"
eval_changed_tree
exit $fail
