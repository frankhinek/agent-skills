#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GIT="$(type -P git)"
REAL_RM="$(type -P rm)"
SYSTEM_BASH="${SYSTEM_BASH:-/bin/bash}"
ORIGINAL_PATH="$PATH"
TEST_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(mktemp -d "$TEST_PARENT/linked-records-vendor-provenance.XXXXXX")"
SOURCE="$TEST_ROOT/source"
PROJECTS="$TEST_ROOT/projects"
SNAPSHOTS="$TEST_ROOT/snapshots"
SHIMS="$TEST_ROOT/shims"
GIT_SPY_LOG="$TEST_ROOT/git-calls"
HOSTILE_GLOBAL="$TEST_ROOT/hostile-global.gitconfig"
HOSTILE_SYSTEM="$TEST_ROOT/hostile-system.gitconfig"
HOSTILE_HOME="$TEST_ROOT/hostile-home"
SAFE_URL="https://github.com/example/linked-records-fixture"
SECRET_SENTINEL="f05-secret-sentinel"
SKILLS=(linked-records linked-records-claims linked-records-upkeep)

unset BASH_ENV ENV
unset -f git 2>/dev/null || true
unset -f rm 2>/dev/null || true

cleanup() {
  case "$TEST_ROOT" in
  "$TEST_PARENT/linked-records-vendor-provenance."*) "$REAL_RM" -rf -- "$TEST_ROOT" ;;
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

assert_omits() {
  local name="$1"
  local output="$2"
  local unexpected="$3"
  if printf '%s\n' "$output" | grep -Fq -- "$unexpected"; then
    fail "$name unexpectedly printed '$unexpected': $output"
  fi
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

configure_repo() {
  local root="$1"
  mkdir -p "$root/.git-hooks"
  "$REAL_GIT" -C "$root" config user.name "Vendor Provenance Test"
  "$REAL_GIT" -C "$root" config user.email "vendor-provenance@example.invalid"
  "$REAL_GIT" -C "$root" config commit.gpgsign false
  "$REAL_GIT" -C "$root" config core.hooksPath .git-hooks
}

run_vendor() {
  set +e
  RUN_OUTPUT="$(
    PATH="$SHIMS:$ORIGINAL_PATH" \
      VENDOR_TEST_REAL_GIT="$REAL_GIT" \
      VENDOR_TEST_SOURCE="$SOURCE" \
      VENDOR_TEST_GIT_LOG="$GIT_SPY_LOG" \
      CURL_HOME="$HOSTILE_HOME" \
      GIT_CONFIG_GLOBAL="$HOSTILE_GLOBAL" \
      GIT_CONFIG_SYSTEM="$HOSTILE_SYSTEM" \
      GIT_PROXY_SSL_CERT="$SECRET_SENTINEL" \
      GIT_SSL_CAINFO="$SECRET_SENTINEL" \
      GIT_SSL_CERT="$SECRET_SENTINEL" \
      GIT_SSL_KEY="$SECRET_SENTINEL" \
      GIT_SSL_NO_VERIFY=1 \
      HOME="$HOSTILE_HOME" \
      NETRC="$HOSTILE_HOME/.netrc" \
      XDG_CONFIG_HOME="$HOSTILE_HOME" \
      "$SYSTEM_BASH" "$SOURCE/vendor.sh" "$@" 2>&1
  )"
  RUN_STATUS=$?
  set -e
}

replace_provenance() {
  local manifest="$1"
  local value="$2"
  awk -v value="$value" '
    /^# vendored-from:/ { if (!done) print "# vendored-from: " value; done = 1; next }
    { print }
  ' "$manifest" >"$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
}

make_project() {
  local name="$1"
  local root="$PROJECTS/$name"
  mkdir -p "$root"
  run_vendor --copy "$root"
  [ "$RUN_STATUS" -eq 0 ] || fail "$name copy failed: $RUN_OUTPUT"
  printf '%s\n' "$root"
}

assert_invalid_manifest() {
  local name="$1"
  local value="$2"
  local root="$PROJECTS/invalid-$name"
  local manifest="$root/.agents/skills/.vendored-manifest"

  cp -R "$BASELINE/." "$root/"
  replace_provenance "$manifest" "$value"
  : >"$GIT_SPY_LOG"
  snapshot_tree "$root" "$SNAPSHOTS/$name.before"
  run_vendor --check "$root"
  [ "$RUN_STATUS" -eq 1 ] ||
    fail "$name returned $RUN_STATUS instead of 1: $RUN_OUTPUT"
  assert_contains "$name" "$RUN_OUTPUT" "provenance : invalid"
  assert_contains "$name" "$RUN_OUTPUT" "published  : unknown (invalid provenance)"
  assert_omits "$name" "$RUN_OUTPUT" "$value"
  [ ! -s "$GIT_SPY_LOG" ] ||
    fail "$name invoked git: $(sed -n '1,20p' "$GIT_SPY_LOG")"
  snapshot_tree "$root" "$SNAPSHOTS/$name.after"
  cmp -s "$SNAPSHOTS/$name.before" "$SNAPSHOTS/$name.after" ||
    fail "$name changed the project tree"
}

mkdir -p "$SOURCE/lib" "$SOURCE/skills" "$PROJECTS" "$SNAPSHOTS" "$SHIMS" \
  "$HOSTILE_HOME"
printf 'machine github.com login attacker password %s\n' "$SECRET_SENTINEL" > \
  "$HOSTILE_HOME/.netrc"
cp "$REPO/vendor.sh" "$SOURCE/vendor.sh"
cp -R "$REPO/lib/." "$SOURCE/lib/"
for skill in "${SKILLS[@]}"; do
  cp -R "$REPO/skills/$skill" "$SOURCE/skills/$skill"
done
printf '%s\n' 'fixture source' >"$SOURCE/README.md"
"$REAL_GIT" -C "$SOURCE" init -q
configure_repo "$SOURCE"
"$REAL_GIT" -C "$SOURCE" add -A
"$REAL_GIT" -C "$SOURCE" commit -q -m "fixture source"
"$REAL_GIT" -C "$SOURCE" remote add origin \
  'git@github.com:example/linked-records-fixture.git'

cat >"$HOSTILE_GLOBAL" <<'EOF'
[url "https://evil.invalid/global/"]
	insteadOf = https://github.com/
[protocol "ext"]
	allow = always
EOF
cat >"$HOSTILE_SYSTEM" <<'EOF'
[url "ext::system-helper "]
	insteadOf = https://github.com/
[protocol "ext"]
	allow = always
EOF

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'set -euo pipefail'
  printf '%s\n' 'is_remote=no'
  printf '%s\n' 'url=""'
  printf '%s\n' 'for arg in "$@"; do'
  printf '%s\n' '  [ "$arg" = ls-remote ] && is_remote=yes'
  printf '%s\n' '  case "$arg" in https://*) url="$arg" ;; esac'
  printf '%s\n' 'done'
  printf '%s\n' 'if [ "$is_remote" = yes ]; then'
  printf '%s\n' '  printf "ls-remote %s\n" "$url" >>"$VENDOR_TEST_GIT_LOG"'
  printf '%s\n' '  [ "$url" = "https://github.com/example/linked-records-fixture" ] || exit 91'
  printf '%s\n' '  [ "${GIT_ALLOW_PROTOCOL:-}" = https ] || exit 92'
  printf '%s\n' '  [ "${GIT_CONFIG_NOSYSTEM:-}" = 1 ] || exit 93'
  printf '%s\n' '  [ "${GIT_CONFIG_GLOBAL:-}" = /dev/null ] || exit 94'
  printf '%s\n' '  [ "${GIT_CONFIG_COUNT:-}" = 0 ] || exit 95'
  printf '%s\n' '  [ "${GIT_DIR:-}" = /dev/null ] || exit 96'
  printf '%s\n' '  [ "${GIT_TERMINAL_PROMPT:-}" = 0 ] || exit 98'
  printf '%s\n' '  [ "${GIT_ASKPASS:-}" = /usr/bin/false ] || exit 99'
  printf '%s\n' '  [ "${SSH_ASKPASS:-}" = /usr/bin/false ] || exit 100'
  printf '%s\n' '  [ "${GCM_INTERACTIVE:-}" = never ] || exit 101'
  printf '%s\n' '  [ "${HOME:-}" = /dev/null ] || exit 103'
  printf '%s\n' '  [ "${CURL_HOME:-}" = /dev/null ] || exit 104'
  printf '%s\n' '  [ "${XDG_CONFIG_HOME:-}" = /dev/null ] || exit 105'
  printf '%s\n' '  [ -z "${GIT_SSL_NO_VERIFY+x}" ] || exit 106'
  printf '%s\n' '  [ -z "${GIT_SSL_CERT+x}" ] || exit 107'
  printf '%s\n' '  [ -z "${GIT_SSL_KEY+x}" ] || exit 108'
  printf '%s\n' '  [ -z "${GIT_SSL_CAINFO+x}" ] || exit 109'
  printf '%s\n' '  [ -z "${GIT_PROXY_SSL_CERT+x}" ] || exit 110'
  printf '%s\n' '  [ -z "${NETRC+x}" ] || exit 111'
  printf '%s\n' '  case "$*" in'
  printf '%s\n' '  *"-c protocol.allow=never -c protocol.https.allow=always -c credential.helper= ls-remote "*) ;;'
  printf '%s\n' '  *) exit 102 ;;'
  printf '%s\n' '  esac'
  printf '%s\n' '  resolved="$("$VENDOR_TEST_REAL_GIT" ls-remote --get-url "$url")"'
  printf '%s\n' '  [ "$resolved" = "$url" ] || exit 97'
  printf '%s\n' '  source_head="$(unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE; "$VENDOR_TEST_REAL_GIT" -C "$VENDOR_TEST_SOURCE" rev-parse HEAD)"'
  printf '%s\n' '  printf "%s\tHEAD\n" "$source_head"'
  printf '%s\n' '  exit 0'
  printf '%s\n' 'fi'
  printf '%s\n' 'exec "$VENDOR_TEST_REAL_GIT" "$@"'
} >"$SHIMS/git"
chmod +x "$SHIMS/git"

BASELINE="$(make_project baseline)"
manifest="$BASELINE/.agents/skills/.vendored-manifest"
grep -Fxq -- "# vendored-from: $SAFE_URL" "$manifest" ||
  fail "SCP source was not stored as canonical HTTPS provenance"

: >"$GIT_SPY_LOG"
snapshot_tree "$BASELINE" "$SNAPSHOTS/valid.before"
run_vendor --check "$BASELINE"
[ "$RUN_STATUS" -eq 0 ] || fail "valid check failed: $RUN_OUTPUT"
assert_contains valid "$RUN_OUTPUT" "provenance : $SAFE_URL"
assert_contains valid "$RUN_OUTPUT" "published  : current"
[ "$(wc -l <"$GIT_SPY_LOG" | tr -d ' ')" -eq 1 ] ||
  fail "valid check did not make exactly one constrained remote query"
snapshot_tree "$BASELINE" "$SNAPSHOTS/valid.after"
cmp -s "$SNAPSHOTS/valid.before" "$SNAPSHOTS/valid.after" ||
  fail "valid check changed the project tree"

"$REAL_GIT" -C "$SOURCE" remote set-url origin \
  'https://github.com/example/linked-records-fixture.git'
https_project="$(make_project https-source)"
grep -Fxq -- "# vendored-from: $SAFE_URL" \
  "$https_project/.agents/skills/.vendored-manifest" ||
  fail "HTTPS source was not stored as canonical provenance"

"$REAL_GIT" -C "$SOURCE" remote set-url origin \
  "https://alice:$SECRET_SENTINEL@github.com/example/linked-records-fixture.git"
credential_project="$PROJECTS/credential-source"
mkdir -p "$credential_project"
run_vendor --copy "$credential_project"
[ "$RUN_STATUS" -eq 0 ] || fail "credential source copy failed: $RUN_OUTPUT"
assert_contains credential-source "$RUN_OUTPUT" "warning: source provenance was omitted"
assert_omits credential-source "$RUN_OUTPUT" "$SECRET_SENTINEL"
credential_manifest="$credential_project/.agents/skills/.vendored-manifest"
assert_omits credential-manifest "$(<"$credential_manifest")" "$SECRET_SENTINEL"
if grep -q '^# vendored-from:' "$credential_manifest"; then
  fail "credential-bearing source persisted provenance"
fi

"$REAL_GIT" -C "$SOURCE" remote set-url origin \
  'ext::untrusted-source-helper'
helper_project="$PROJECTS/helper-source"
mkdir -p "$helper_project"
run_vendor --copy "$helper_project"
[ "$RUN_STATUS" -eq 0 ] || fail "helper source copy failed: $RUN_OUTPUT"
assert_contains helper-source "$RUN_OUTPUT" "warning: source provenance was omitted"
assert_omits helper-source "$RUN_OUTPUT" "ext::untrusted-source-helper"
if grep -q '^# vendored-from:' "$helper_project/.agents/skills/.vendored-manifest"; then
  fail "custom-helper source persisted provenance"
fi

"$REAL_GIT" -C "$SOURCE" remote remove origin
no_origin_project="$PROJECTS/no-origin"
mkdir -p "$no_origin_project"
run_vendor --copy "$no_origin_project"
[ "$RUN_STATUS" -eq 0 ] || fail "no-origin copy failed: $RUN_OUTPUT"
assert_omits no-origin "$RUN_OUTPUT" "source provenance was omitted"
if grep -q '^# vendored-from:' "$no_origin_project/.agents/skills/.vendored-manifest"; then
  fail "source without origin persisted provenance"
fi

"$REAL_GIT" -C "$SOURCE" config --add remote.origin.url \
  'https://github.com/example/first.git'
"$REAL_GIT" -C "$SOURCE" config --add remote.origin.url \
  'https://github.com/example/second.git'
duplicate_origin_project="$PROJECTS/duplicate-origin"
mkdir -p "$duplicate_origin_project"
run_vendor --copy "$duplicate_origin_project"
[ "$RUN_STATUS" -eq 0 ] || fail "duplicate-origin copy failed: $RUN_OUTPUT"
assert_contains duplicate-origin "$RUN_OUTPUT" \
  "warning: source provenance was omitted because origin metadata is invalid."
assert_omits duplicate-origin "$RUN_OUTPUT" 'https://github.com/example/first.git'
assert_omits duplicate-origin "$RUN_OUTPUT" 'https://github.com/example/second.git'
if grep -q '^# vendored-from:' \
  "$duplicate_origin_project/.agents/skills/.vendored-manifest"; then
  fail "source with duplicate origins persisted provenance"
fi

: >"$GIT_SPY_LOG"
set +e
DIRECT_OUTPUT="$(
  PATH="$SHIMS:$ORIGINAL_PATH" \
    VENDOR_TEST_GIT_LOG="$GIT_SPY_LOG" \
    "$SYSTEM_BASH" -c \
    'source "$1"; provenance_remote_head "$2"' \
    _ "$SOURCE/lib/vendor-provenance.sh" 'ext::direct-helper' 2>&1
)"
DIRECT_STATUS=$?
set -e
[ "$DIRECT_STATUS" -ne 0 ] || fail "remote helper accepted invalid direct input"
[ ! -s "$GIT_SPY_LOG" ] || fail "remote helper invoked git for invalid direct input"
assert_omits direct-helper "$DIRECT_OUTPUT" 'ext::direct-helper'

invalid_values=(
  "https://alice:$SECRET_SENTINEL@github.com/example/repo"
  'http://github.com/example/repo'
  'https://evil.invalid/example/repo'
  'ssh://git@github.com/example/repo'
  'file:///tmp/repo'
  '/tmp/repo'
  'git@github.com:example/repo.git'
  'ext::untrusted-helper'
  'custom::untrusted-helper'
  'https://github.com/example/repo?query=yes'
  'https://github.com:443/example/repo'
  'https://github.com/example/repo#fragment'
  'https://github.com/example/repo/extra'
)
index=0
for value in "${invalid_values[@]}"; do
  index=$((index + 1))
  assert_invalid_manifest "value-$index" "$value"
done

duplicate_root="$PROJECTS/invalid-duplicate"
cp -R "$BASELINE/." "$duplicate_root/"
printf '# vendored-from: https://alice:%s@github.com/example/repo\n' \
  "$SECRET_SENTINEL" >> \
  "$duplicate_root/.agents/skills/.vendored-manifest"
: >"$GIT_SPY_LOG"
run_vendor --check "$duplicate_root"
[ "$RUN_STATUS" -eq 1 ] || fail "duplicate provenance returned $RUN_STATUS"
assert_contains duplicate "$RUN_OUTPUT" "provenance : invalid"
assert_omits duplicate "$RUN_OUTPUT" "$SECRET_SENTINEL"
[ ! -s "$GIT_SPY_LOG" ] || fail "duplicate provenance invoked git"

malformed_root="$PROJECTS/invalid-malformed"
cp -R "$BASELINE/." "$malformed_root/"
awk -v secret="$SECRET_SENTINEL" '
  /^# vendored-from:/ {
    print "# vendored-from:https://alice:" secret "@github.com/example/repo"
    next
  }
  { print }
' "$malformed_root/.agents/skills/.vendored-manifest" > \
  "$malformed_root/.agents/skills/.vendored-manifest.tmp"
mv "$malformed_root/.agents/skills/.vendored-manifest.tmp" \
  "$malformed_root/.agents/skills/.vendored-manifest"
: >"$GIT_SPY_LOG"
run_vendor --check "$malformed_root"
[ "$RUN_STATUS" -eq 1 ] || fail "malformed provenance returned $RUN_STATUS"
assert_contains malformed "$RUN_OUTPUT" "provenance : invalid"
assert_omits malformed "$RUN_OUTPUT" "$SECRET_SENTINEL"
[ ! -s "$GIT_SPY_LOG" ] || fail "malformed provenance invoked git"

echo "PASS: vendor provenance trust boundary"
