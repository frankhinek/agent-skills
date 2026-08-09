#!/usr/bin/env bash
# Shared Git-state queries for scenario checkers. EVAL_BASE is the complete
# fixture revision captured after overlays and before the agent runs.

eval_require_base() {
  if [ -z "${EVAL_BASE:-}" ]; then
    echo "ERROR: missing EVAL_BASE" >&2
    return 2
  fi
  if ! git cat-file -e "${EVAL_BASE}^{commit}" 2>/dev/null; then
    echo "ERROR: invalid EVAL_BASE: $EVAL_BASE" >&2
    return 2
  fi
}

eval_tracked_unchanged() {
  git diff --quiet "$EVAL_BASE" -- "$@"
}

eval_tracked_diff() {
  git diff "$EVAL_BASE" -- "$@"
}

eval_untracked() {
  git ls-files --others --exclude-standard -- "$@"
}

# NUL-delimited final-state paths changed since the immutable eval baseline.
# Deleted paths are omitted because there is no remaining content to inspect.
eval_changed_files() {
  git diff --name-only -z --diff-filter=ACMRTUXB "$EVAL_BASE" -- "$@" || return $?
  git ls-files --others --exclude-standard -z -- "$@"
}

eval_tree_unchanged() {
  local untracked
  eval_tracked_unchanged "$@" || return $?
  untracked="$(eval_untracked "$@")" || return $?
  [ -z "$untracked" ]
}

eval_changed_tree() {
  local untracked
  git diff --name-status "$EVAL_BASE" -- "$@" || return $?
  untracked="$(eval_untracked "$@")" || return $?
  if [ -n "$untracked" ]; then
    printf '%s\n' "$untracked" | sed 's/^/?\t/'
  fi
}
