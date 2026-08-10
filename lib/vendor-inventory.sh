#!/usr/bin/env bash
# Typed manifest inventory helpers sourced by vendor.sh.

# Manifest v2 stores one tab-delimited, C-sorted record per copied entry:
#   D <hex path>
#   F <hex path> <executable:0|1> <POSIX cksum> <byte count>
#   L <hex path> <hex link target>
# Hex fields keep path and target parsing independent of whitespace and locale.

INVENTORY_STAT_STYLE=unavailable
if inventory_stat_probe="$(stat -f '%Lp' "$REPO/vendor.sh" 2>/dev/null)"; then
  case "$inventory_stat_probe" in
  "" | *[!0-7]*) ;;
  *) INVENTORY_STAT_STYLE=bsd ;;
  esac
fi
if [ "$INVENTORY_STAT_STYLE" = unavailable ] &&
  inventory_stat_probe="$(stat -c '%a' "$REPO/vendor.sh" 2>/dev/null)"; then
  case "$inventory_stat_probe" in
  "" | *[!0-7]*) ;;
  *) INVENTORY_STAT_STYLE=gnu ;;
  esac
fi
unset inventory_stat_probe

hex_encode() {
  LC_ALL=C od -An -v -tx1 | tr -d ' \n'
}

display_hex() {
  local hex="$1"
  local rest="$1"
  local byte value char output=""

  case "$hex" in
  "" | *[!0-9a-f]*) printf 'hex:%s' "$hex"; return ;;
  esac
  [ $(( ${#hex} % 2 )) -eq 0 ] || {
    printf 'hex:%s' "$hex"
    return
  }

  while [ -n "$rest" ]; do
    byte="${rest:0:2}"
    rest="${rest:2}"
    value=$((16#$byte))
    if [ "$value" -lt 32 ] || [ "$value" -gt 126 ]; then
      printf 'hex:%s' "$hex"
      return
    fi
    printf -v char "\\x$byte"
    output="$output$char"
  done
  printf '%s' "$output"
}

entry_type_name() {
  case "$1" in
  D) printf 'directory' ;;
  F) printf 'file' ;;
  L) printf 'symlink' ;;
  *) printf 'unknown' ;;
  esac
}

unsupported_type_name() {
  local path="$1"
  if [ -p "$path" ]; then
    printf 'fifo'
  elif [ -S "$path" ]; then
    printf 'socket'
  elif [ -b "$path" ]; then
    printf 'block device'
  elif [ -c "$path" ]; then
    printf 'character device'
  else
    printf 'unsupported type'
  fi
}

executable_state() {
  local path="$1"
  local mode

  case "$INVENTORY_STAT_STYLE" in
  bsd) mode="$(stat -f '%Lp' "$path" 2>/dev/null)" ;;
  gnu) mode="$(stat -c '%a' "$path" 2>/dev/null)" ;;
  *) mode="" ;;
  esac
  case "$mode" in
  "" | *[!0-7]*)
    printf 'error: cannot read executable state: %s\n' "$path" >&2
    return 1
    ;;
  esac
  if (( (8#$mode) & 0111 )); then
    printf '1'
  else
    printf '0'
  fi
}

inventory_entry() {
  local physical_path="$1"
  local path="${2:-$1}"
  local encoded_path target_with_marker target encoded_target
  local checksum_output checksum size executable

  if encoded_path="$(printf '%s' "$path" | hex_encode)"; then
    :
  else
    printf 'error: cannot encode vendored path: %s\n' "$path" >&2
    return 1
  fi
  if [ -L "$physical_path" ]; then
    if target_with_marker="$({ readlink -n "$physical_path" || exit $?; printf '\001'; })"; then
      target="${target_with_marker%?}"
    else
      printf 'error: cannot read symlink target: %s\n' "$path" >&2
      return 1
    fi
    if encoded_target="$(printf '%s' "$target" | hex_encode)"; then
      :
    else
      printf 'error: cannot encode symlink target: %s\n' "$path" >&2
      return 1
    fi
    printf 'L\t%s\t%s\n' "$encoded_path" "$encoded_target"
  elif [ -d "$physical_path" ]; then
    printf 'D\t%s\n' "$encoded_path"
  elif [ -f "$physical_path" ]; then
    executable="$(executable_state "$physical_path")" || return 1
    if checksum_output="$(cksum <"$physical_path" 2>/dev/null)"; then
      read -r checksum size _ <<<"$checksum_output"
    else
      printf 'error: cannot checksum vendored file: %s\n' "$path" >&2
      return 1
    fi
    case "$checksum:$size" in
    *[!0-9:]* | :* | *:)
      printf 'error: invalid checksum result for vendored file: %s\n' "$path" >&2
      return 1
      ;;
    esac
    printf 'F\t%s\t%s\t%s\t%s\n' \
      "$encoded_path" "$executable" "$checksum" "$size"
  else
    printf 'error: unsupported vendored entry: %s (%s)\n' \
      "$path" "$(unsupported_type_name "$physical_path")" >&2
    return 1
  fi
}

inventory_skills() {
  local root="$1"
  local s d path relative canonical

  {
    for s in "${SKILLS[@]}"; do
      d="$root/$s"
      [ -L "$d" ] && continue
      [ -e "$d" ] || continue
      find "$d" -print0 || exit $?
    done
  } | while IFS= read -r -d '' path; do
    relative="${path#"$root"/}"
    canonical=".agents/skills/$relative"
    inventory_entry "$path" "$canonical" || exit $?
  done | LC_ALL=C sort
}

inventory_vendored() {
  inventory_skills ".agents/skills"
}

manifest_field() {
  sed -n "s/^# $1: //p" "$MANIFEST" 2>/dev/null | head -1
}

# Prints one strict, nonempty manifest header value. Status 1 means the header
# is absent; status 2 means it is duplicate or malformed.
manifest_strict_field_value() {
  local field="$1"

  LC_ALL=C awk -v field="$field" -v prefix="# $field: " '
    $0 ~ "^#[[:space:]]*" field "([[:space:]:]|$)" {
      candidates++
      if (index($0, prefix) == 1) {
        candidate = substr($0, length(prefix) + 1)
        nonspace = candidate
        gsub(/[[:space:]]/, "", nonspace)
        if (nonspace != "") {
          values++
          value = candidate
        } else malformed = 1
      } else malformed = 1
    }
    END {
      if (candidates == 0) exit 1
      if (candidates != 1 || values != 1 || malformed) exit 2
      print value
    }
  ' "$MANIFEST" 2>/dev/null
}

# Status 1 means no format header (legacy); status 2 means a duplicate or
# malformed format header.
manifest_format_value() {
  manifest_strict_field_value manifest-format
}

# Object-ID syntax is validated by the caller so missing and invalid payload
# identities can be reported distinctly.
manifest_payload_id_value() {
  manifest_strict_field_value payload-id
}

git_object_id_valid() {
  local object_id="$1"

  case "$object_id" in
  "" | *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#object_id}" -eq 40 ] || [ "${#object_id}" -eq 64 ]
}

# Hashes a canonical list of the three committed managed-skill tree IDs. This
# excludes unrelated repository paths while retaining Git's object identity.
# Status 2 means the revision does not contain the complete managed payload;
# status 1 means Git could not inspect or hash it.
git_managed_payload_id() {
  local root="$1"
  local revision="$2"
  local skill path record metadata record_path mode type tree payload_id

  payload_id="$({
    for skill in "${SKILLS[@]}"; do
      path="skills/$skill"
      record="$(GIT_NO_LAZY_FETCH=1 git -C "$root" ls-tree \
        "$revision" -- "$path" 2>/dev/null)" || exit 1
      [ -n "$record" ] || exit 2
      metadata="${record%%$'\t'*}"
      record_path="${record#*$'\t'}"
      read -r mode type tree <<<"$metadata"
      [ "$mode" = 040000 ] && [ "$type" = tree ] && \
        [ "$record_path" = "$path" ] || exit 2
      git_object_id_valid "$tree" || exit 2
      printf '%s\t%s\n' "$skill" "$tree"
    done
  } | GIT_NO_LAZY_FETCH=1 git -C "$root" hash-object --stdin)" || return $?
  git_object_id_valid "$payload_id" || return 1
  printf '%s\n' "$payload_id"
}

# Emits a manifest-format inventory for the raw committed managed trees. This
# intentionally bypasses checkout filters: copy mode must prove that the bytes,
# types, and executable state on disk equal the objects named by the payload.
inventory_git_skills() {
  local root="$1"
  local revision="$2"
  local record metadata path mode type object canonical encoded_path
  local checksum_output checksum size executable encoded_target

  {
    for skill in "${SKILLS[@]}"; do
      GIT_NO_LAZY_FETCH=1 git -C "$root" ls-tree -r -t -z \
        "$revision" -- "skills/$skill" || exit $?
    done
  } | while IFS= read -r -d '' record; do
    metadata="${record%%$'\t'*}"
    path="${record#*$'\t'}"
    [ "$path" != skills ] || continue
    read -r mode type object <<<"$metadata"
    canonical=".agents/${path}"
    if encoded_path="$(printf '%s' "$canonical" | hex_encode)"; then
      :
    else
      printf 'error: cannot encode vendored path: %s\n' "$canonical" >&2
      exit 1
    fi
    case "$mode:$type" in
    040000:tree)
      printf 'D\t%s\n' "$encoded_path"
      ;;
    100644:blob | 100755:blob)
      [ "$mode" = 100755 ] && executable=1 || executable=0
      checksum_output="$(GIT_NO_LAZY_FETCH=1 git -C "$root" \
        cat-file blob "$object" | cksum)" || exit 1
      read -r checksum size _ <<<"$checksum_output"
      case "$checksum:$size" in
      *[!0-9:]* | :* | *:) exit 1 ;;
      esac
      printf 'F\t%s\t%s\t%s\t%s\n' \
        "$encoded_path" "$executable" "$checksum" "$size"
      ;;
    120000:blob)
      if encoded_target="$(GIT_NO_LAZY_FETCH=1 git -C "$root" \
        cat-file blob "$object" | hex_encode)"; then
        :
      else
        printf 'error: cannot encode symlink target: %s\n' "$canonical" >&2
        exit 1
      fi
      printf 'L\t%s\t%s\n' "$encoded_path" "$encoded_target"
      ;;
    *)
      printf 'error: unsupported committed entry: %s (%s %s)\n' \
        "$path" "$mode" "$type" >&2
      exit 1
      ;;
    esac
  done | LC_ALL=C sort
}

# Copy mode copies the physical source tree, so cleanliness alone is not
# enough: filters, index flags, ignored paths, empty directories, and gitlinks
# can all make clean checkout bytes differ from the committed payload.
# Status 2 means a real source/commit difference; status 1 means inspection
# failed and therefore cannot authorize copying.
git_managed_source_pristine() {
  local root="$1"
  local revision="$2"
  local committed physical

  committed="$(inventory_git_skills "$root" "$revision")" || return 1
  physical="$(inventory_skills "$root/skills")" || return 1
  [ "$committed" != "$physical" ] || return 0

  printf 'source differences from committed managed payload:\n' >&2
  report_inventory_changes "$committed" "$physical" >&2 || return 1
  return 2
}

manifest_inventory() {
  sed -n '/^#/!p' "$MANIFEST"
}

validate_inventory() {
  LC_ALL=C awk '
    BEGIN { FS = "\t"; valid = 1 }
    function is_hex(value, allow_empty) {
      if (value == "") return allow_empty
      return length(value) % 2 == 0 && value ~ /^[0-9a-f]+$/
    }
    {
      if ($1 == "D") ok = NF == 2 && is_hex($2, 0)
      else if ($1 == "F")
        ok = NF == 5 && is_hex($2, 0) && $3 ~ /^[01]$/ &&
          $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/
      else if ($1 == "L") ok = NF == 3 && is_hex($2, 0) && is_hex($3, 1)
      else ok = 0
      if (!ok || seen[$2]++) valid = 0
    }
    END { exit NR > 0 && valid ? 0 : 1 }
  '
}

inventory_change_records() {
  local expected="$1"
  local actual="$2"

  LC_ALL=C awk '
    BEGIN { FS = "\t"; OFS = "\t" }
    FILENAME == ARGV[1] {
      path = $2
      expected_type[path] = $1
      expected_exec[path] = $3
      expected_value[path] = $4 OFS $5
      expected_target[path] = $3
      next
    }
    {
      path = $2
      actual_type[path] = $1
      actual_exec[path] = $3
      actual_value[path] = $4 OFS $5
      actual_target[path] = $3
    }
    END {
      for (path in expected_type) {
        if (!(path in actual_type)) {
          print path, "removed", expected_type[path], expected_target[path]
          continue
        }
        if (expected_type[path] != actual_type[path]) {
          print path, "type", expected_type[path], actual_type[path]
          continue
        }
        if (expected_type[path] == "F") {
          if (expected_value[path] != actual_value[path])
            print path, "content"
          if (expected_exec[path] != actual_exec[path])
            print path, "executable", expected_exec[path], actual_exec[path]
        } else if (expected_type[path] == "L" &&
                   expected_target[path] != actual_target[path]) {
          print path, "target", expected_target[path], actual_target[path]
        }
      }
      for (path in actual_type) {
        if (!(path in expected_type))
          print path, "added", actual_type[path], actual_target[path]
      }
    }
  ' <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") |
    LC_ALL=C sort
}

report_inventory_changes() {
  local expected="$1"
  local actual="$2"
  local changes comparison_status
  local path_hex change before after path type target

  if changes="$(inventory_change_records "$expected" "$actual" 2>&1)"; then
    comparison_status=0
  else
    comparison_status=$?
  fi
  if [ "$comparison_status" -ne 0 ]; then
    printf 'error: inventory comparison failed (status %s)\n' \
      "$comparison_status" >&2
    return "$comparison_status"
  fi

  while IFS=$'\t' read -r path_hex change before after; do
    [ -n "$path_hex" ] || continue
    path="$(display_hex "$path_hex")"
    case "$change" in
    added | removed)
      type="$(entry_type_name "$before")"
      if [ "$before" = L ]; then
        target="$(display_hex "$after")"
        printf '  %s: %s (%s -> %s)\n' "$change" "$path" "$type" "$target"
      else
        printf '  %s: %s (%s)\n' "$change" "$path" "$type"
      fi
      ;;
    type)
      printf '  type changed: %s (%s -> %s)\n' "$path" \
        "$(entry_type_name "$before")" "$(entry_type_name "$after")"
      ;;
    content)
      printf '  content changed: %s\n' "$path"
      ;;
    executable)
      [ "$before" = 1 ] && before=yes || before=no
      [ "$after" = 1 ] && after=yes || after=no
      printf '  executable changed: %s (%s -> %s)\n' "$path" "$before" "$after"
      ;;
    target)
      printf '  target changed: %s (%s -> %s)\n' "$path" \
        "$(display_hex "$before")" "$(display_hex "$after")"
      ;;
    esac
  done <<<"$changes"
}
