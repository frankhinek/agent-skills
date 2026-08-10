#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$REPO/install.sh"
REAL_RM="$(type -P rm)"
REAL_LN="$(type -P ln)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/linked-records-install.XXXXXX")"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)
FAILURE_BIN="$TEST_ROOT/failure-bin"
RUN_INSTALLER="$INSTALLER"
FAIL_RM=""
FAIL_LN=""

unset BASH_ENV ENV
unset -f rm ln 2>/dev/null || true

mkdir -p "$FAILURE_BIN"
"$REAL_LN" -s "$REPO/tests/fixtures/install-failure/command" "$FAILURE_BIN/rm"
"$REAL_LN" -s "$REPO/tests/fixtures/install-failure/command" "$FAILURE_BIN/ln"

cleanup() {
  case "$TEST_ROOT" in
  "${TMPDIR:-/tmp}/linked-records-install."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
  *) echo "refusing to clean unexpected test path: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_install() {
  local home="$1"
  shift
  mkdir -p "$home"
  set +e
  RUN_OUTPUT="$(HOME="$home" PATH="$FAILURE_BIN:$PATH" \
    INSTALL_TEST_REAL_RM="$REAL_RM" INSTALL_TEST_REAL_LN="$REAL_LN" \
    INSTALL_TEST_FAIL_RM="$FAIL_RM" INSTALL_TEST_FAIL_LN="$FAIL_LN" \
    /bin/bash "$RUN_INSTALLER" "$@" 2>&1)"
  RUN_RC=$?
  set -e
}

assert_links() {
  local target="$1"
  local skill
  for skill in "${SKILLS[@]}"; do
    [ -L "$target/$skill" ] || fail "$target/$skill is not a symlink"
    [ "$REPO/skills/$skill" -ef "$target/$skill" ] ||
      fail "$target/$skill does not resolve to the repository skill"
  done
}

assert_output() {
  if [[ "$RUN_OUTPUT" != *"$1"* ]]; then
    fail "missing output '$1': $RUN_OUTPUT"
  fi
}

assert_no_output() {
  if [[ "$RUN_OUTPUT" == *"$1"* ]]; then
    fail "unexpected output '$1': $RUN_OUTPUT"
  fi
}

home="$TEST_ROOT/home"
missing="$TEST_ROOT/missing"
run_install "$home" "$missing"
[ "$RUN_RC" -eq 0 ] || fail "missing target returned $RUN_RC: $RUN_OUTPUT"
assert_links "$missing"
assert_output "complete  $missing (installed=3, already-correct=0)"

run_install "$home" "$missing"
[ "$RUN_RC" -eq 0 ] || fail "idempotent run returned $RUN_RC: $RUN_OUTPUT"
assert_links "$missing"
assert_output "complete  $missing (installed=0, already-correct=3)"

identical="$TEST_ROOT/identical"
mkdir -p "$identical"
for skill in "${SKILLS[@]}"; do
  cp -R "$REPO/skills/$skill" "$identical/$skill"
done
run_install "$home" "$identical"
[ "$RUN_RC" -eq 0 ] || fail "identical-copy run returned $RUN_RC: $RUN_OUTPUT"
assert_links "$identical"
assert_output "complete  $identical (installed=3, already-correct=0)"

symlinks="$TEST_ROOT/symlinks"
mkdir -p "$symlinks"
ln -s "$REPO/skills/linked-records" "$symlinks/linked-records"
ln -s "$REPO/skills/linked-records" "$symlinks/linked-records-claims"
ln -s "$TEST_ROOT/missing-source" "$symlinks/linked-records-upkeep"
run_install "$home" "$symlinks"
[ "$RUN_RC" -eq 0 ] || fail "symlink repair returned $RUN_RC: $RUN_OUTPUT"
assert_links "$symlinks"
assert_output "complete  $symlinks (installed=2, already-correct=1)"

partial="$TEST_ROOT/partial"
mkdir -p "$partial"
cp -R "$REPO/skills/linked-records" "$partial/linked-records"
printf '%s\n' 'local change' >>"$partial/linked-records/SKILL.md"
run_install "$home" "$partial"
[ "$RUN_RC" -eq 1 ] || fail "partial target returned $RUN_RC instead of 1: $RUN_OUTPUT"
grep -Fq 'local change' "$partial/linked-records/SKILL.md" ||
  fail "divergent local copy was changed"
[ -L "$partial/linked-records-claims" ] || fail "partial target suppressed linked-records-claims"
[ -L "$partial/linked-records-upkeep" ] || fail "partial target suppressed linked-records-upkeep"
assert_output "partial  $partial (installed=2, already-correct=0, skipped=1, failed=0)"
assert_no_output "complete  $partial"

later="$TEST_ROOT/later-extra"
run_install "$home" "$partial" "$later"
[ "$RUN_RC" -eq 1 ] || fail "multiple targets returned $RUN_RC instead of 1: $RUN_OUTPUT"
assert_links "$later"
assert_output "partial  $partial (installed=0, already-correct=2, skipped=1, failed=0)"
assert_output "complete  $later (installed=3, already-correct=0)"

ordering_home="$TEST_ROOT/ordering-home"
explicit="$TEST_ROOT/explicit-before-defaults"
mkdir -p "$ordering_home/.claude" "$ordering_home/.codex"
: >"$ordering_home/.claude/skills"
run_install "$ordering_home" "$explicit"
[ "$RUN_RC" -eq 1 ] || fail "default failure returned $RUN_RC instead of 1: $RUN_OUTPUT"
assert_links "$explicit"
assert_links "$ordering_home/.codex/skills"
assert_output "complete  $explicit (installed=3, already-correct=0)"
assert_output "partial  $ordering_home/.claude/skills (installed=0, already-correct=0, skipped=0, failed=3)"
assert_output "complete  $ordering_home/.codex/skills (installed=3, already-correct=0)"
explicit_line="$(printf '%s\n' "$RUN_OUTPUT" | grep -nF "complete  $explicit" | sed -n '1s/:.*//p')"
default_line="$(printf '%s\n' "$RUN_OUTPUT" | grep -nF "partial  $ordering_home/.claude/skills" | sed -n '1s/:.*//p')"
[ "$explicit_line" -lt "$default_line" ] || fail "explicit target was not processed before defaults"

extra_one="$TEST_ROOT/extra-one"
extra_two="$TEST_ROOT/extra-two"
run_install "$home" "$extra_one" "$extra_two"
[ "$RUN_RC" -eq 0 ] || fail "successful extra targets returned $RUN_RC: $RUN_OUTPUT"
assert_links "$extra_one"
assert_links "$extra_two"
assert_output "complete  $extra_one (installed=3, already-correct=0)"
assert_output "complete  $extra_two (installed=3, already-correct=0)"

defaults_home="$TEST_ROOT/defaults-home"
mkdir -p "$defaults_home/.claude" "$defaults_home/.codex"
run_install "$defaults_home"
[ "$RUN_RC" -eq 0 ] || fail "defaults-only run returned $RUN_RC: $RUN_OUTPUT"
assert_links "$defaults_home/.claude/skills"
assert_links "$defaults_home/.codex/skills"
assert_output "complete  $defaults_home/.claude/skills (installed=3, already-correct=0)"
assert_output "complete  $defaults_home/.codex/skills (installed=3, already-correct=0)"
assert_output "skip  $defaults_home/.config/goose/skills (tool not present)"

empty_home="$TEST_ROOT/empty-home"
run_install "$empty_home"
[ "$RUN_RC" -eq 0 ] || fail "empty defaults-only run returned $RUN_RC: $RUN_OUTPUT"
assert_no_output "complete  "

fixture_repo="$TEST_ROOT/fixture-repo"
mkdir -p "$fixture_repo"
cp "$INSTALLER" "$fixture_repo/install.sh"
cp -R "$REPO/skills" "$fixture_repo/skills"
RUN_INSTALLER="$fixture_repo/install.sh"

self_target="$TEST_ROOT/self-target"
"$REAL_LN" -s "$fixture_repo/skills" "$self_target"
run_install "$empty_home" "$self_target"
[ "$RUN_RC" -eq 0 ] || fail "self-target run returned $RUN_RC: $RUN_OUTPUT"
for skill in "${SKILLS[@]}"; do
  [ -d "$fixture_repo/skills/$skill" ] || fail "self-target removed source skill $skill"
  [ ! -L "$fixture_repo/skills/$skill" ] || fail "self-target replaced source skill $skill with a link"
done
assert_output "complete  $self_target (installed=0, already-correct=3)"

rm_failure="$TEST_ROOT/rm-failure"
rm_later="$TEST_ROOT/rm-later"
mkdir -p "$rm_failure"
for skill in "${SKILLS[@]}"; do
  cp -R "$fixture_repo/skills/$skill" "$rm_failure/$skill"
done
FAIL_RM="$rm_failure/linked-records-claims"
run_install "$empty_home" "$rm_failure" "$rm_later"
[ "$RUN_RC" -eq 1 ] || fail "rm failure returned $RUN_RC instead of 1: $RUN_OUTPUT"
assert_output "partial  $rm_failure (installed=2, already-correct=0, skipped=0, failed=1)"
assert_output "complete  $rm_later (installed=3, already-correct=0)"
FAIL_RM=""

ln_failure="$TEST_ROOT/ln-failure"
ln_later="$TEST_ROOT/ln-later"
FAIL_LN="$ln_failure/linked-records-claims"
run_install "$empty_home" "$ln_failure" "$ln_later"
[ "$RUN_RC" -eq 1 ] || fail "ln failure returned $RUN_RC instead of 1: $RUN_OUTPUT"
assert_output "partial  $ln_failure (installed=2, already-correct=0, skipped=0, failed=1)"
assert_output "complete  $ln_later (installed=3, already-correct=0)"
FAIL_LN=""

missing_source_repo="$TEST_ROOT/missing-source-repo"
mkdir -p "$missing_source_repo"
cp "$INSTALLER" "$missing_source_repo/install.sh"
cp -R "$REPO/skills" "$missing_source_repo/skills"
"$REAL_RM" -rf "$missing_source_repo/skills/linked-records-claims"
RUN_INSTALLER="$missing_source_repo/install.sh"
missing_source="$TEST_ROOT/missing-source-target"
run_install "$empty_home" "$missing_source"
[ "$RUN_RC" -eq 1 ] || fail "missing source returned $RUN_RC instead of 1: $RUN_OUTPUT"
assert_output "partial  $missing_source (installed=2, already-correct=0, skipped=0, failed=1)"
[ -L "$missing_source/linked-records" ] || fail "missing source suppressed earlier skill"
[ -L "$missing_source/linked-records-upkeep" ] || fail "missing source suppressed later skill"

RUN_INSTALLER="$INSTALLER"

echo "PASS: installer target state and aggregation contract"
