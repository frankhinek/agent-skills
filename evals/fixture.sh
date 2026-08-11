#!/usr/bin/env bash
# Build the base eval fixture (a tiny local-first note app governed by
# linked-records) at the given path, vendored + committed.
set -euo pipefail

DEST_INPUT="${1:?usage: fixture.sh <dest-dir>}"
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$EVALS")"

DEST_PARENT="$(dirname -- "$DEST_INPUT")"
DEST_NAME="$(basename -- "$DEST_INPUT")"
mkdir -p -- "$DEST_PARENT"
DEST_PARENT="$(cd "$DEST_PARENT" && pwd -P)"
DEST="$DEST_PARENT/$DEST_NAME"

cleanup_fixture() {
  local status=$?
  trap - EXIT INT TERM
  if ! rm -rf -- "$DEST"; then
    echo "fixture.sh: cleanup failed; partial fixture remains at: $DEST" >&2
  fi
  exit "$status"
}

interrupt_fixture() {
  local status="$1"
  trap - INT TERM
  exit "$status"
}

if ! mkdir -- "$DEST"; then
  echo "fixture.sh: destination must not already exist and must be creatable: $DEST" >&2
  exit 1
fi
trap cleanup_fixture EXIT
# macOS Bash 3.2 does not run an EXIT trap for an uncaught INT or TERM.
trap 'interrupt_fixture 130' INT
trap 'interrupt_fixture 143' TERM

mkdir -p "$DEST/app" "$DEST/external" "$DEST/specs/CLAIM-single-writer"
cd "$DEST"

cat >README.md <<'EOF'
# notekeep

Tiny local-first note keeper demo.
EOF

cat >.gitignore <<'EOF'
data/
EOF

cat >app/store.py <<'EOF'
import json
import os

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")


class Store:
    """The single writer for everything under data/."""

    def write(self, key, value):
        os.makedirs(DATA_DIR, exist_ok=True)
        with open(os.path.join(DATA_DIR, key + ".json"), "w") as f:
            json.dump(value, f)

    def read(self, key):
        try:
            with open(os.path.join(DATA_DIR, key + ".json")) as f:
                return json.load(f)
        except FileNotFoundError:
            return None
EOF

cat >app/handler.py <<'EOF'
from .store import Store

store = Store()


def save_note(note_id, text):
    store.write("note-" + note_id, {"text": text})


def get_note(note_id):
    return store.read("note-" + note_id)
EOF

cat >app/config.py <<'EOF'
import json
import os


def load_config(path=None):
    path = path or os.environ.get("APP_CONFIG", "config.json")
    with open(path) as f:
        return json.load(f)
EOF

cat >app/metadata.py <<'EOF'
def build_import_metadata(source_id):
    return {"source_id": source_id}
EOF

cat >app/exporter.py <<'EOF'
from .store import Store

store = Store()


def export_note(note_id):
    note = store.read("note-" + note_id)
    return note["text"] if note is not None else None
EOF

cat >external/source-id-policy.md <<'EOF'
# Imported Note Source Policy

Every imported note metadata object must retain its non-empty `source_id`.
This policy applies to all imports.
EOF

cat >specs/GATE-local-only.md <<'EOF'
# GATE-local-only: All user data stays on the local machine

## Gate

User data (notes, config, anything under `data/`) is stored and processed
on the local machine only. No network sync, upload, or remote backup of
user data, by any transport.

## Justification

The user chose this tool specifically for offline, private note storage;
losing that property would defeat the product's reason to exist.
EOF

cat >specs/ARCH-app.md <<'EOF'
# ARCH-app: Note app shape

Handlers (`app/handler.py`) accept note operations and delegate all
persistence to `Store` (`app/store.py`), the only component that touches
`data/`. Configuration is read by `app/config.py` at startup. Constrained
by [GATE-local-only](./GATE-local-only.md); the single-writer property is
[CLAIM-single-writer](./CLAIM-single-writer.md).
EOF

cat >specs/REQ-import-source.md <<'EOF'
# REQ-import-source: Imported notes retain their source identifier

## Source

`external/source-id-policy.md`, mandatory for all imports.

## Acceptance

`build_import_metadata` returns a non-empty `source_id` unchanged from its
input for every imported note.
EOF

cat >specs/SPEC-note-payload.md <<'EOF'
# SPEC-note-payload: Saved and exported note payloads use text

## Record justification

The payload key spans `app/handler.py` writes and `app/exporter.py` reads, so
neither module is a coherent owner.

`save_note` stores note content under `text`; `export_note` reads `text` and
returns its value.
EOF

cat >specs/CLAIM-single-writer.md <<'EOF'
# CLAIM-single-writer: data/ has one writer

Only `Store.write` in `app/store.py` creates or modifies files under
`data/`; every other component submits writes through it.
EOF

cat >specs/CLAIM-single-writer/proof.md <<'EOF'
Property: only `Store.write` creates or modifies files under `data/`.

1. `code` — `app/store.py` is the only module referencing `DATA_DIR` or
   opening files under `data/` for writing.
2. `enum` — writers found by searching `open(` with write modes across
   `app/`: exactly one, in `Store.write`.

Axiom: no external process writes into `data/`.
Residuals: none.
Weakest links: both lemmas are `code`/`enum` rung; a lint pinning the
single `open(..., "w")` site would promote them.
EOF

cat >specs/CLAIM-single-writer/verification.md <<'EOF'
Verified at fixture baseline, 2026-08-05, independent pass over app/:
regenerated the writer enumeration, checked handler and config paths.
Result: pass
The argument survived checking as of this date.
EOF

"$REPO/vendor.sh" "$DEST" >/dev/null

git init -q
git config user.name "linked-records eval"
git config user.email "linked-records-eval@localhost"
git config commit.gpgsign false
mkdir -p .git/eval-hooks
git config core.hooksPath .git/eval-hooks
git add -A
git commit -qm "baseline"

trap - EXIT INT TERM
