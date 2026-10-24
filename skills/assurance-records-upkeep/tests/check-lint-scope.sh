#!/usr/bin/env bash
# Exercise record discovery and explicit archival exclusions through the CLI.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LINTER="$SCRIPT_DIR/../lint.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assurance-records-scope.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
failed=0
executed=0

put() {
  local path="$1"
  shift
  mkdir -p "${path%/*}"
  printf '%s\n' "$@" >"$path"
}

check() {
  local name="$1" root="$2" expected_rc="$3" expected="$4" output rc=0
  output="$("$LINTER" "$root" 2>&1)" || rc=$?
  executed=$((executed + 1))
  if [ "$rc" -ne "$expected_rc" ] || ! printf '%s\n' "$output" | grep -Fq -- "$expected"; then
    printf 'FAIL %s: expected exit %s and %s; got exit %s\n%s\n' \
      "$name" "$expected_rc" "$expected" "$rc" "$output"
    failed=$((failed + 1))
  else
    printf 'PASS %s\n' "$name"
  fi
}

root="$TEST_ROOT/instructions"
put "$root/specs/REQ-live.md" '# REQ-live: Live obligation' '' 'Keep accepted work.'
put "$root/specs/AGENTS.md" '# Instructions' '' 'Follow REQ-live.'
put "$root/specs/CLAUDE.md" '@AGENTS.md'
put "$root/component/specs/REQ-other.md" '# REQ-other: Other obligation' '' 'Keep other work.'
put "$root/component/specs/AGENTS.md" '# Local instructions'
put "$root/component/specs/CLAUDE.md" '@AGENTS.md'
check instruction-files "$root" 0 'clean (2 records)'
put "$root/specs/AGENTS.md" '# Instructions' '' 'Follow REQ-missing.'
check instruction-references "$root" 1 './specs/AGENTS.md:3: [dangling-ref] references non-existent record REQ-missing'

root="$TEST_ROOT/other-markdown"
put "$root/specs/README.md" '# Record index'
put "$root/specs/notes.md" '# Notes'
check index-still-rejected "$root" 1 '[no-index]'
check non-record-still-rejected "$root" 1 '[type]'

root="$TEST_ROOT/archive"
put "$root/specs/REQ-live.md" '# REQ-live: Live obligation' '' 'Keep accepted work.'
put "$root/verification/results/snapshot/specs/REQ-live.md" '# REQ-live: Archived obligation' '' 'Keep historical work.'
put "$root/verification/results/snapshot/old.py" '# REQ-historical-only'
put "$root/verification/current/specs/REQ-validation.md" '# REQ-validation: Live validation' '' 'Keep live validation in scope.'
check archives-are-live-by-default "$root" 1 '[unique-id]'
put "$root/.assuranceignore" '# Captured source, not the live corpus.' '' 'verification/results/snapshot'
check explicit-archive-exclusion "$root" 0 'clean (2 records)'
check reported-exclusion "$root" 0 'assurance-records lint: excluded directory: verification/results/snapshot'
put "$root/verification/current/specs/REQ-live.md" '# REQ-live: Duplicate live obligation' '' 'Still an error.'
check live-validation-still-checked "$root" 1 '[unique-id]'
rm "$root/verification/current/specs/REQ-live.md"
put "$root/verification/results/snapshot-copy/specs/REQ-live.md" '# REQ-live: Sibling obligation' '' 'Still an error.'
check exclusion-is-not-a-prefix "$root" 1 '[unique-id]'
rm "$root/verification/results/snapshot-copy/specs/REQ-live.md"
put "$root/verification/results/snapshot/specs/REQ-archived-only.md" '# REQ-archived-only: Archived obligation' '' 'Not a live target.'
put "$root/src/app.py" '# REQ-archived-only'
check archive-cannot-satisfy-live-reference "$root" 1 './src/app.py:1: [dangling-ref] references non-existent record REQ-archived-only'

root="$TEST_ROOT/literal-path"
put "$root/specs/REQ-live.md" '# REQ-live: Live obligation' '' 'Keep accepted work.'
put "$root/snapshots/run [1]*?/specs/REQ-live.md" '# REQ-live: Snapshot' '' 'Historical.'
put "$root/.assuranceignore" 'snapshots/run [1]*?'
check literal-path-metacharacters "$root" 0 'clean (1 records)'
put "$root/snapshots/run 1abc/specs/REQ-live.md" '# REQ-live: Sibling' '' 'Live.'
check metacharacters-do-not-hide-siblings "$root" 1 '[unique-id]'

root="$TEST_ROOT/config"
mkdir -p "$root/snapshots/old"
put "$root/specs/REQ-live.md" '# REQ-live: Live obligation' '' 'Keep accepted work.'
put "$root/plain-file" 'Not a directory.'
ln -s snapshots "$root/link"
ln -s "$TEST_ROOT" "$root/outside"
for excluded in . /specs ../specs snapshots/../specs ./snapshots snapshots//old snapshots/ missing plain-file link/old outside/config; do
  put "$root/.assuranceignore" "$excluded"
  check "invalid-exclusion-$excluded" "$root" 2 '[setup]'
done
put "$root/.assuranceignore" '' '# Empty configuration is allowed.'
check empty-configuration "$root" 0 'clean (1 records)'
rm "$root/.assuranceignore"
put "$root/settings" 'snapshots/old'
ln -s settings "$root/.assuranceignore"
check configuration-symlink "$root" 2 '[setup]'
rm "$root/.assuranceignore"
mkdir "$root/.assuranceignore"
check configuration-directory "$root" 2 '[setup]'

root="$TEST_ROOT/no-specs"
put "$root/.assuranceignore" 'missing'
check bad-config-without-records "$root" 2 '[setup]'

root="$TEST_ROOT/generated"
put "$root/specs/REQ-live.md" '# REQ-live: Live obligation' '' 'Keep accepted work.'
for generated in build dist .venv venv vendor node_modules .git .agents; do
  put "$root/$generated/dependency/specs/REQ-live.md" '# REQ-live: Generated copy' '' 'Not live.'
done
put "$root/.custom [client]/skill/SKILL.md" '# Agent skill'
put "$root/.custom [client]/skill/specs/REQ-live.md" '# REQ-live: Skill example' '' 'Not live.'
check shared-discovery-boundaries "$root" 0 'clean (1 records)'

if [ "$failed" -ne 0 ]; then
  printf 'lint scope regressions: %s failure(s), %s cases\n' "$failed" "$executed"
  exit 1
fi
printf 'lint scope regressions: clean (%s cases)\n' "$executed"
