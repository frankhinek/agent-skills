#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_CP="$(type -P cp)"
REAL_GIT="$(type -P git)"
REAL_MKDIR="$(type -P mkdir)"
REAL_MKTEMP="$(type -P mktemp)"
REAL_RM="$(type -P rm)"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$($REAL_MKTEMP -d "$TEST_PARENT/linked-records-regressions.XXXXXX")"
SNAPSHOT="$TEST_ROOT/repo"
SUITES=(
  tests/check-vendor-arguments.sh
  tests/check-vendor-inventory.sh
  tests/check-vendor-provenance.sh
  tests/check-vendor-staleness.sh
  tests/check-vendor-state.sh
  tests/check-vendor-transaction.sh
  tests/check-install.sh
  skills/linked-records-upkeep/tests/check-lint.sh
)

unset BASH_ENV ENV
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE
unset GIT_CEILING_DIRECTORIES GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
unset -f cp 2>/dev/null || true
unset -f git 2>/dev/null || true
unset -f mkdir 2>/dev/null || true
unset -f mktemp 2>/dev/null || true
unset -f rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-regressions."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
  *) echo "refusing to clean unexpected test root: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fixture_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    "$REAL_GIT" -C "$SNAPSHOT" "$@"
}

"$REAL_MKDIR" -p "$SNAPSHOT"
"$REAL_CP" -R \
  "$REPO/vendor.sh" \
  "$REPO/install.sh" \
  "$REPO/lib" \
  "$REPO/skills" \
  "$REPO/tests" \
  "$SNAPSHOT/"

fixture_git init --quiet
"$REAL_MKDIR" -p "$SNAPSHOT/.git/test-hooks"
fixture_git config user.name "Linked Records Tests"
fixture_git config user.email "tests@linked-records.invalid"
fixture_git config commit.gpgsign false
fixture_git config core.hooksPath .git/test-hooks
fixture_git remote add origin https://github.com/example/linked-records-fixture.git
fixture_git add vendor.sh install.sh lib skills tests
fixture_git commit --quiet -m "Build regression fixture"

for suite in "${SUITES[@]}"; do
  if [ ! -f "$SNAPSHOT/$suite" ]; then
    echo "FAIL: required regression suite is missing: $suite" >&2
    exit 1
  fi
done

for discovered_suite in \
  "$SNAPSHOT"/tests/check-vendor-*.sh \
  "$SNAPSHOT"/tests/check-install*.sh \
  "$SNAPSHOT"/skills/linked-records-upkeep/tests/check-lint*.sh; do
  [ -f "$discovered_suite" ] || continue
  discovered_suite="${discovered_suite#"$SNAPSHOT/"}"
  registered=false
  for suite in "${SUITES[@]}"; do
    if [ "$suite" = "$discovered_suite" ]; then
      registered=true
      break
    fi
  done
  if [ "$registered" = false ]; then
    echo "FAIL: unregistered regression suite: $discovered_suite" >&2
    exit 1
  fi
done

for suite in "${SUITES[@]}"; do
  printf '\n==> %s\n' "$suite"
  (
    cd "$SNAPSHOT"
    "$BASH" "$suite"
  )
done

printf '\nPASS: all %s contract regression suites\n' "${#SUITES[@]}"
