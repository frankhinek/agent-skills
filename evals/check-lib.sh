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

# Every scenario is governed by the vendored skills present at EVAL_BASE.
# Ignore rules are deliberately bypassed so an injected skill cannot hide
# behind .gitignore, .git/info/exclude, or a configured global excludes file.
eval_check_governing_skills() {
  local baseline_index tracked_changes untracked untracked_rc

  baseline_index="$(mktemp "${TMPDIR:-/tmp}/linked-records-skill-index.XXXXXX")" || {
    echo "FAIL: governing skill integrity could not be evaluated"
    return 2
  }
  rm -f -- "$baseline_index" || {
    echo "FAIL: governing skill integrity could not be evaluated"
    return 2
  }
  if ! GIT_INDEX_FILE="$baseline_index" git read-tree "$EVAL_BASE"; then
    rm -f -- "$baseline_index"
    echo "FAIL: governing skill integrity could not be evaluated"
    return 2
  fi

  tracked_changes="$(GIT_INDEX_FILE="$baseline_index" \
    git diff --name-status "$EVAL_BASE" -- .agents/skills/)" || {
    rm -f -- "$baseline_index"
    echo "FAIL: governing skill integrity could not be evaluated"
    return 2
  }
  untracked="$(GIT_INDEX_FILE="$baseline_index" \
    git ls-files --others -- .agents/skills/)"
  untracked_rc=$?

  if [ "$untracked_rc" -ne 0 ]; then
    rm -f -- "$baseline_index"
    echo "FAIL: governing skill integrity could not be evaluated"
    return 2
  fi
  if ! rm -f -- "$baseline_index"; then
    echo "FAIL: governing skill integrity could not be evaluated"
    return 2
  fi
  if [ -z "$tracked_changes" ] && [ -z "$untracked" ]; then
    echo "PASS: governing skills match eval baseline"
    return 0
  fi

  echo "FAIL: governing skills changed:"
  if [ -n "$tracked_changes" ]; then
    printf '%s\n' "$tracked_changes" | sed 's/^/  /'
  fi
  if [ -n "$untracked" ]; then
    printf '%s\n' "$untracked" | sed 's/^/  ?\t/'
  fi
  return 1
}
