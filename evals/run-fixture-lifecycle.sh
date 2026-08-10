#!/usr/bin/env bash
# Runner-owned temporary fixture lifecycle. Source from evals/run.sh.

EVAL_FIXTURE_ROOT=""
EVAL_FIXTURE_PREFIX=""
EVAL_FIXTURE_CHILD_PID=""
EVAL_FIXTURE_INTERRUPT_STATUS=0

eval_fixture_root_is_safe() {
  local candidate="$1"
  local suffix

  [ -n "$candidate" ] && [ -d "$candidate" ] && [ ! -L "$candidate" ] ||
    return 1
  case "$candidate" in
  "$EVAL_FIXTURE_PREFIX"*) ;;
  *) return 1 ;;
  esac
  suffix="${candidate#"$EVAL_FIXTURE_PREFIX"}"
  [ -n "$suffix" ] || return 1
  case "$suffix" in
  */*) return 1 ;;
  esac
}

eval_fixture_cleanup() {
  local status=$?
  local retain=0

  trap - EXIT INT TERM
  if [ -z "$EVAL_FIXTURE_ROOT" ]; then
    exit "$status"
  fi

  case "$EVAL_FIXTURE_RETENTION" in
  always) retain=1 ;;
  failed) [ "$status" -eq 0 ] || retain=1 ;;
  esac
  if [ "$retain" -eq 1 ]; then
    echo "retained eval fixtures: $EVAL_FIXTURE_ROOT" >&2
    exit "$status"
  fi

  if [ ! -e "$EVAL_FIXTURE_ROOT" ] && [ ! -L "$EVAL_FIXTURE_ROOT" ]; then
    exit "$status"
  fi
  if ! eval_fixture_root_is_safe "$EVAL_FIXTURE_ROOT"; then
    echo "cleanup refused; unsafe eval fixture root remains at: $EVAL_FIXTURE_ROOT" >&2
    [ "$status" -ne 0 ] || status=1
    exit "$status"
  fi
  if ! rm -rf -- "$EVAL_FIXTURE_ROOT"; then
    echo "cleanup failed; eval fixtures remain at: $EVAL_FIXTURE_ROOT" >&2
    [ "$status" -ne 0 ] || status=1
  fi
  exit "$status"
}

eval_fixture_interrupt() {
  local status="$1"
  local signal="$2"

  EVAL_FIXTURE_INTERRUPT_STATUS="$status"
  if [ -z "$EVAL_FIXTURE_CHILD_PID" ]; then
    exit "$status"
  fi
  kill -"$signal" "$EVAL_FIXTURE_CHILD_PID" 2>/dev/null || true
  # Non-interactive Bash starts background children with INT ignored. TERM is
  # the portable stop signal that makes an INT-directed runner reclaim them.
  if [ "$signal" = INT ]; then
    kill -TERM "$EVAL_FIXTURE_CHILD_PID" 2>/dev/null || true
  fi
}

eval_fixture_wait_for_child() {
  local status

  wait "$EVAL_FIXTURE_CHILD_PID"
  status=$?
  while kill -0 "$EVAL_FIXTURE_CHILD_PID" 2>/dev/null; do
    wait "$EVAL_FIXTURE_CHILD_PID"
    status=$?
  done
  EVAL_FIXTURE_CHILD_PID=""
  if [ "$EVAL_FIXTURE_INTERRUPT_STATUS" -ne 0 ]; then
    return "$EVAL_FIXTURE_INTERRUPT_STATUS"
  fi
  return "$status"
}

eval_fixture_temp_init() {
  local tmp_parent
  local raw
  local physical
  local rc

  tmp_parent="${TMPDIR:-/tmp}"
  tmp_parent="$(cd "$tmp_parent" 2>/dev/null && pwd -P)" || {
    echo "eval fixture temporary parent is unavailable: ${TMPDIR:-/tmp}" >&2
    return 1
  }
  EVAL_FIXTURE_PREFIX="${tmp_parent%/}/linked-records-eval."

  raw="$(mktemp -d "${EVAL_FIXTURE_PREFIX}XXXXXX")"
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
    echo "eval fixture temporary root creation failed (exit $rc)" >&2
    return 1
  fi
  if ! eval_fixture_root_is_safe "$raw"; then
    echo "unsafe eval fixture temporary root; refusing to use: $raw" >&2
    return 1
  fi

  # Arm cleanup once the returned path is narrow enough to remove safely.
  EVAL_FIXTURE_ROOT="$raw"
  trap eval_fixture_cleanup EXIT
  # macOS Bash 3.2 does not reliably run EXIT for an uncaught INT or TERM.
  trap 'eval_fixture_interrupt 130 INT' INT
  trap 'eval_fixture_interrupt 143 TERM' TERM

  physical="$(cd "$raw" 2>/dev/null && pwd -P)" || {
    echo "eval fixture temporary root is unreadable: $raw" >&2
    return 1
  }
  if ! eval_fixture_root_is_safe "$physical"; then
    echo "unsafe eval fixture temporary root; refusing to use: $raw" >&2
    return 1
  fi

  EVAL_FIXTURE_ROOT="$physical"
}
