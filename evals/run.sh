#!/usr/bin/env bash
# Run the linked-records behavioral evals against a harness.
#
# Usage: run.sh <claude|codex> [scenario ...]     (default: all scenarios)
#
# Each scenario: build a fresh fixture, apply the scenario overlay if any,
# run the harness headlessly with the scenario prompt, then run check.sh
# (mechanical postconditions) inside the fixture. Final responses and
# diagnostic logs go to results/<date>-<harness>/logs/ (gitignored); the
# summary is committed.
set -uo pipefail

EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${1:?usage: run.sh <claude|codex> [scenario ...]}"
shift || true

case "$HARNESS" in
claude|codex) ;;
*)
  echo "unsupported harness: $HARNESS" >&2
  exit 2
  ;;
esac

DATE="$(date +%Y-%m-%d)"
OUT="$EVALS/results/$DATE-$HARNESS${EVAL_LABEL:+-$EVAL_LABEL}"
mkdir -p "$OUT/logs"

if [ $# -gt 0 ]; then
  SCENARIOS=("$@")
else
  SCENARIOS=()
  for d in "$EVALS/scenarios"/*/; do SCENARIOS+=("$(basename "$d")"); done
fi

summary="$OUT/summary.md"
{
  echo "# Eval run: $HARNESS, $DATE"
  echo
  case "$HARNESS" in
  claude) version="$(claude --version 2>/dev/null | head -1)" ;;
  codex) version="$(codex --version 2>/dev/null | head -1)" ;;
  esac
  echo "- version: ${version:-unavailable}"
  [ -z "${EVAL_CLAUDE_ARGS:-}${EVAL_CODEX_ARGS:-}" ] ||
    echo "- pinned args: ${EVAL_CLAUDE_ARGS:-}${EVAL_CODEX_ARGS:-}"
  echo "- final responses and diagnostics: logs/"
  echo "- mechanical checks below; judge escalation quality from final responses"
  echo
} >"$summary"

record_invalid() {
  local scenario="$1"
  local reason="$2"
  local detail="$3"
  local duration="$4"
  {
    echo "## $scenario"
    echo
    echo "- status: INVALID: $reason"
    echo "- detail: $detail"
    echo "- duration: ${duration}s"
    echo "- diagnostics: logs/$scenario.log"
    echo
  } >>"$summary"
  echo "INVALID: $reason — $detail"
  echo
}

overall=0
for s in "${SCENARIOS[@]}"; do
  sd="$EVALS/scenarios/$s"
  [ -d "$sd" ] || { echo "unknown scenario: $s" >&2; continue; }

  log="$OUT/logs/$s.log"
  response="$OUT/logs/$s.response.txt"
  : >"$log"
  : >"$response"
  echo "== $s ($HARNESS) =="
  start="$(date +%s)"

  fixture_parent="$(mktemp -d)"
  mktemp_rc=$?
  if [ "$mktemp_rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "setup" "temporary fixture creation failed (exit $mktemp_rc)" 0
    continue
  fi
  fx="$fixture_parent/fixture"

  "$EVALS/fixture.sh" "$fx" >>"$log" 2>&1
  setup_rc=$?
  if [ "$setup_rc" -eq 0 ] && [ -d "$sd/overlay" ]; then
    (cp -R "$sd/overlay/." "$fx/" &&
      git -C "$fx" add -A &&
      git -C "$fx" commit -qm "overlay") >>"$log" 2>&1
    setup_rc=$?
  fi
  if [ "$setup_rc" -ne 0 ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "setup" "fixture construction failed (exit $setup_rc)" "$dur"
    continue
  fi

  base="$(git -C "$fx" rev-parse --verify 'HEAD^{commit}' 2>>"$log")"
  base_rc=$?
  if [ "$base_rc" -ne 0 ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "setup" "eval baseline could not be resolved (exit $base_rc)" "$dur"
    continue
  fi

  if [ ! -s "$sd/prompt.txt" ] || [ ! -s "$sd/response-signal.regex" ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "scenario configuration" "prompt or response signal is missing/empty" "$dur"
    continue
  fi

  prompt="$(cat "$sd/prompt.txt")"
  pattern="$(sed -n '1p' "$sd/response-signal.regex")"
  if [ -z "$pattern" ]; then
    dur=$(($(date +%s) - start))
    overall=1
    record_invalid "$s" "scenario configuration" "response signal is blank" "$dur"
    continue
  fi

  case "$HARNESS" in
  claude)
    # shellcheck disable=SC2086
    (cd "$fx" && claude -p "$prompt" --dangerously-skip-permissions ${EVAL_CLAUDE_ARGS:-} \
      --output-format text </dev/null) >"$response" 2>>"$log"
    rc=$?
    ;;
  codex)
    # shellcheck disable=SC2086
    codex exec ${EVAL_CODEX_ARGS:-} -s workspace-write -C "$fx" \
      -o "$response" "$prompt" </dev/null >>"$log" 2>&1
    rc=$?
    ;;
  esac
  dur=$(($(date +%s) - start))

  if [ "$rc" -ne 0 ]; then
    overall=1
    record_invalid "$s" "harness (exit $rc)" "agent command did not complete; grading skipped" "$dur"
    continue
  fi

  grep -q '[^[:space:]]' "$response"
  response_rc=$?
  if [ "$response_rc" -ne 0 ]; then
    overall=1
    if [ "$response_rc" -eq 1 ]; then
      record_invalid "$s" "missing response" "agent completed without a final response; grading skipped" "$dur"
    else
      record_invalid "$s" "response artifact" "final response could not be evaluated (exit $response_rc)" "$dur"
    fi
    continue
  fi

  grep -qiE -e "$pattern" "$response"
  signal_rc=$?
  if [ "$signal_rc" -gt 1 ]; then
    overall=1
    record_invalid "$s" "response signal" "response signal could not be evaluated (exit $signal_rc)" "$dur"
    continue
  fi

  check="$(cd "$fx" && EVAL_BASE="$base" bash "$sd/check.sh" 2>&1)"
  crc=$?
  scenario_status=PASS
  if [ "$signal_rc" -ne 0 ] || [ "$crc" -ne 0 ]; then
    scenario_status=FAIL
    overall=1
  fi

  {
    echo "## $s"
    echo
    echo "- status: $scenario_status"
    if [ "$signal_rc" -eq 0 ]; then
      echo "- PASS: response signal"
    else
      echo "- FAIL: response signal — no task-engagement signal in final response; judge response"
    fi
    if [ "$crc" -eq 0 ]; then
      echo "- PASS: postconditions"
    else
      echo "- FAIL: postconditions (exit $crc)"
    fi
    echo "- agent exit $rc, ${dur}s"
    echo "- baseline: $base"
    echo "- final response: logs/$s.response.txt"
    echo "- diagnostics: logs/$s.log"
    echo
    echo '```'
    echo "$check"
    echo '```'
    echo
  } >>"$summary"
  echo "$scenario_status: $s"
  if [ "$signal_rc" -eq 0 ]; then
    echo "PASS: response signal"
  else
    echo "FAIL: response signal"
  fi
  if [ "$crc" -eq 0 ]; then
    echo "PASS: postconditions"
  else
    echo "FAIL: postconditions (exit $crc)"
  fi
  echo "$check"
  echo
done

echo "summary: $summary"
exit "$overall"
