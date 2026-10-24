#!/usr/bin/env bash
# Three-skill inventory upgrades and version-1 transaction recovery.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/assurance-upgrade.XXXXXX")"
OLD="$ROOT/old"
REAL_MV="$(type -P mv)"
REAL_GIT="$(type -P git)"
cleanup() {
  case "$ROOT" in
  "${TMPDIR:-/tmp}/assurance-upgrade."*) rm -rf -- "$ROOT" ;;
  *) echo "refusing unexpected cleanup: $ROOT" >&2 ;;
  esac
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Emit the historical three-entry inventory and version-1 transaction protocol.
# This fixture changes only the sender's managed set and protocol version.
mkdir -p "$OLD"
cp -R "$REPO/vendor.sh" "$REPO/lib" "$REPO/skills" "$OLD/"
sed 's/ assurance-records-bug-hunt)/)/' "$OLD/vendor.sh" >"$OLD/vendor.new"
mv "$OLD/vendor.new" "$OLD/vendor.sh"
sed 's/VENDOR_TRANSACTION_VERSION=2/VENDOR_TRANSACTION_VERSION=1/' \
  "$OLD/lib/vendor-transaction.sh" >"$OLD/lib/transaction.new"
mv "$OLD/lib/transaction.new" "$OLD/lib/vendor-transaction.sh"
rm -rf "$OLD/skills/assurance-records-bug-hunt"
git -C "$OLD" init -q
git -C "$OLD" config user.name 'Upgrade tests'
git -C "$OLD" config user.email 'upgrade@localhost'
git -C "$OLD" config commit.gpgsign false
git -C "$OLD" config core.hooksPath /dev/null
git -C "$OLD" add vendor.sh lib skills
git -C "$OLD" commit -qm 'Three-skill protocol fixture'

make_old() {
  project="$ROOT/$1"
  mkdir -p "$project/.agents/skills/unrelated"
  printf 'retain\n' >"$project/.agents/skills/unrelated/KEEP"
  bash "$OLD/vendor.sh" --copy "$project" >"$ROOT/output" 2>&1 ||
    fail "legacy setup: $(cat "$ROOT/output")"
}
snapshot() {
  (cd "$project" && find . -type f -exec cksum {} \; &&
    find . -type l -exec ls -ld {} \;) | LC_ALL=C sort >"$1"
}
run_new() {
  rc=0
  PATH="$REPO/tests/fixtures/git-unreachable:$PATH" \
    VENDOR_TEST_REAL_GIT="$REAL_GIT" bash "$REPO/vendor.sh" "$@" "$project" \
    >"$ROOT/output" 2>&1 || rc=$?
}
expect_rc() {
  [ "$rc" -eq "$1" ] || fail "expected $1, got $rc: $(cat "$ROOT/output")"
}

make_old pristine
old_payload="$(sed -n 's/^# payload-id: //p' "$project/.agents/skills/.vendored-manifest")"
snapshot "$ROOT/before"
run_new --check
expect_rc 1
grep -q 'assurance-records-bug-hunt: missing' "$ROOT/output" || fail 'missing upgrade not reported'
snapshot "$ROOT/after"
cmp -s "$ROOT/before" "$ROOT/after" || fail 'upgrade check mutated installation'
run_new --copy
expect_rc 0
[ -f "$project/.agents/skills/assurance-records-bug-hunt/SKILL.md" ] || fail 'new skill absent'
new_payload="$(sed -n 's/^# payload-id: //p' "$project/.agents/skills/.vendored-manifest")"
[ "$old_payload" != "$new_payload" ] || fail 'payload identity ignored fourth skill'
run_new --copy
expect_rc 0
run_new --check
expect_rc 0

for kind in old-edit new-directory new-link; do
  make_old "$kind"
  case "$kind" in
  old-edit) printf 'local edit\n' >>"$project/.agents/skills/assurance-records/SKILL.md" ;;
  new-directory)
    mkdir "$project/.agents/skills/assurance-records-bug-hunt"
    printf 'local skill\n' >"$project/.agents/skills/assurance-records-bug-hunt/KEEP"
    ;;
  new-link) ln -s unrelated "$project/.agents/skills/assurance-records-bug-hunt" ;;
  esac
  snapshot "$ROOT/before"
  run_new --copy
  expect_rc 1
  snapshot "$ROOT/after"
  cmp -s "$ROOT/before" "$ROOT/after" || fail "$kind lost local work"
done

mkdir "$ROOT/shim"
cat >"$ROOT/shim/mv" <<'SH'
#!/usr/bin/env bash
argc=$#
eval "source_arg=\${$((argc - 1))}"
eval "target_arg=\${$argc}"
"$UPGRADE_REAL_MV" "$@" || exit $?
case "$UPGRADE_KILL_AT:$source_arg:$target_arg" in
fourth:*/stage/assurance-records-bug-hunt:.agents/skills/assurance-records-bug-hunt|\
first:*/stage/assurance-records:.agents/skills/assurance-records)
  /bin/kill -KILL "$PPID"; exit 137 ;;
committed:*/phase.new:*/phase)
  if [ "$(cat "$target_arg")" = committed ]; then
    /bin/kill -KILL "$PPID"; exit 137
  fi ;;
esac
SH
chmod +x "$ROOT/shim/mv"
interrupt_copy() {
  local vendor="$1" point="$2"
  rc=0
  PATH="$ROOT/shim:$PATH" UPGRADE_REAL_MV="$REAL_MV" UPGRADE_KILL_AT="$point" \
    bash "$vendor" --copy "$project" >"$ROOT/output" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail 'interruption did not fire'
  [ -d "$project/.agents/.vendor-transaction" ] || fail 'transaction evidence absent'
}

make_old interrupted-upgrade
snapshot "$ROOT/before"
interrupt_copy "$REPO/vendor.sh" fourth
run_new --copy
expect_rc 1
snapshot "$ROOT/after"
cmp -s "$ROOT/before" "$ROOT/after" || fail 'interrupted upgrade did not restore old pack'
[ ! -e "$project/.agents/skills/assurance-records-bug-hunt" ] || fail 'rollback retained fourth skill'
run_new --copy
expect_rc 0

# Both recovery phases must ignore a fourth entry the old updater never owned.
for phase in first committed; do
  make_old "legacy-$phase"
  mkdir "$project/.agents/skills/assurance-records-bug-hunt"
  printf 'user-owned\n' >"$project/.agents/skills/assurance-records-bug-hunt/KEEP"
  snapshot "$ROOT/before"
  interrupt_copy "$OLD/vendor.sh" "$phase"
  run_new --check
  expect_rc 1
  grep -q 'incomplete vendor updater transaction' "$ROOT/output" || fail 'legacy transaction not recognized'
  run_new --copy
  expect_rc 1
  [ ! -e "$project/.agents/.vendor-transaction" ] || fail 'legacy recovery retained transaction'
  snapshot "$ROOT/after"
  cmp -s "$ROOT/before" "$ROOT/after" || fail "legacy $phase recovery changed unowned state"
done

# A truncated new-format transaction cannot masquerade as a legacy one.
make_old truncated
interrupt_copy "$REPO/vendor.sh" fourth
presence="$project/.agents/.vendor-transaction/original-presence"
sed '/^assurance-records-bug-hunt/d' "$presence" >"$ROOT/presence"
mv "$ROOT/presence" "$presence"
snapshot "$ROOT/before"
run_new --copy
expect_rc 1
grep -q 'invalid vendor transaction metadata' "$ROOT/output" || fail 'truncated v2 accepted'
snapshot "$ROOT/after"
cmp -s "$ROOT/before" "$ROOT/after" || fail 'invalid transaction was changed'

echo 'PASS: three-skill upgrade, collision preservation, and versioned recovery'
