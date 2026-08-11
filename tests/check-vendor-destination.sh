#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO/vendor.sh"
REAL_GIT="$(type -P git)"
REAL_RM="$(type -P rm)"
ORIGINAL_PATH="$PATH"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/linked-records-vendor-destination.XXXXXX")"
PROJECTS="$TEST_ROOT/projects"
OUTSIDE="$TEST_ROOT/outside"
SNAPSHOTS="$TEST_ROOT/snapshots"
SHIMS="$TEST_ROOT/shims"
GIT_LOG="$TEST_ROOT/git-calls"

unset BASH_ENV ENV
unset -f git 2>/dev/null || true
unset -f rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-vendor-destination."*)
    "$REAL_RM" -rf -- "$TEST_ROOT"
    ;;
  *) echo "refusing to clean unexpected test root: $TEST_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local name="$1"
  local output="$2"
  local expected="$3"
  printf '%s\n' "$output" | grep -Fq -- "$expected" ||
    fail "$name omitted '$expected': $output"
}

snapshot_tree() {
  local root="$1"
  local output="$2"
  (
    cd "$root"
    find . -type d -print | LC_ALL=C sort | sed 's/^/d /'
    find . -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      printf 'f '
      cksum "$path"
    done
    find . -type l -print | LC_ALL=C sort | while IFS= read -r path; do
      printf 'l %s -> %s\n' "$path" "$(readlink "$path")"
    done
  ) >"$output"
}

make_git_shim() {
  cat >"$SHIMS/git" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VENDOR_TEST_GIT_LOG"
exec "$VENDOR_TEST_REAL_GIT" "$@"
SHIM
  chmod +x "$SHIMS/git"
}

run_vendor() {
  set +e
  RUN_OUTPUT="$(
    PATH="$SHIMS:$ORIGINAL_PATH" \
      VENDOR_TEST_GIT_LOG="$GIT_LOG" \
      VENDOR_TEST_REAL_GIT="$REAL_GIT" \
      "$VENDOR" "$@" 2>&1
  )"
  RUN_STATUS=$?
  set -e
}

prepare_boundary() {
  local boundary="$1"
  local project="$2"
  local outside="$3"

  mkdir -p "$project" "$outside"
  printf '%s\n' 'preserve external content' >"$outside/sentinel.txt"

  case "$boundary" in
  agents-symlink)
    mkdir -p "$outside/agents"
    ln -s "$outside/agents" "$project/.agents"
    ;;
  skills-symlink)
    mkdir -p "$project/.agents" "$outside/skills"
    ln -s "$outside/skills" "$project/.agents/skills"
    ;;
  agents-pointer-symlink)
    ln -s "$outside/sentinel.txt" "$project/AGENTS.md"
    ;;
  agents-file)
    printf '%s\n' 'not a directory' >"$project/.agents"
    ;;
  skills-file)
    mkdir -p "$project/.agents"
    printf '%s\n' 'not a directory' >"$project/.agents/skills"
    ;;
  agents-pointer-directory)
    mkdir -p "$project/AGENTS.md"
    ;;
  *) fail "unknown boundary fixture: $boundary" ;;
  esac
}

assert_rejected_without_mutation() {
  local boundary="$1"
  local mode="$2"
  local unsafe_path="$3"
  local name="$boundary-$mode"
  local project="$PROJECTS/$name"
  local outside="$OUTSIDE/$name"
  local args=()
  local managed_outside=""

  prepare_boundary "$boundary" "$project" "$outside"
  case "$boundary:$mode" in
  agents-symlink:*force) managed_outside="$outside/agents/skills" ;;
  skills-symlink:*force) managed_outside="$outside/skills" ;;
  esac
  if [ -n "$managed_outside" ]; then
    mkdir -p "$managed_outside/linked-records"
    printf '%s\n' 'preserve managed external content' \
      >"$managed_outside/linked-records/sentinel.txt"
  fi
  snapshot_tree "$project" "$SNAPSHOTS/$name.project.before"
  snapshot_tree "$outside" "$SNAPSHOTS/$name.outside.before"
  : >"$GIT_LOG"

  case "$mode" in
  copy) args=(--copy "$project") ;;
  link) args=(--link "$project") ;;
  check) args=(--check "$project") ;;
  copy-force) args=(--copy --force "$project") ;;
  link-force) args=(--link --force "$project") ;;
  *) fail "unknown mode: $mode" ;;
  esac

  run_vendor "${args[@]}"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name" "$RUN_OUTPUT" "error: unsafe vendor destination: $unsafe_path"

  snapshot_tree "$project" "$SNAPSHOTS/$name.project.after"
  snapshot_tree "$outside" "$SNAPSHOTS/$name.outside.after"
  cmp -s "$SNAPSHOTS/$name.project.before" "$SNAPSHOTS/$name.project.after" ||
    fail "$name changed the project tree"
  cmp -s "$SNAPSHOTS/$name.outside.before" "$SNAPSHOTS/$name.outside.after" ||
    fail "$name changed the external tree"
  [ ! -s "$GIT_LOG" ] ||
    fail "$name called git before rejecting the destination: $(sed -n '1,20p' "$GIT_LOG")"
}

mkdir -p "$PROJECTS" "$OUTSIDE" "$SNAPSHOTS" "$SHIMS"
make_git_shim

for boundary in agents-symlink skills-symlink agents-pointer-symlink; do
  case "$boundary" in
  agents-symlink) unsafe_path=.agents ;;
  skills-symlink) unsafe_path=.agents/skills ;;
  agents-pointer-symlink) unsafe_path=AGENTS.md ;;
  esac
  for mode in copy link check copy-force link-force; do
    assert_rejected_without_mutation "$boundary" "$mode" "$unsafe_path"
  done
done

assert_rejected_without_mutation agents-file copy .agents
assert_rejected_without_mutation skills-file copy .agents/skills
assert_rejected_without_mutation agents-pointer-directory copy AGENTS.md

echo "PASS: unsafe vendor destinations are rejected without mutation"
