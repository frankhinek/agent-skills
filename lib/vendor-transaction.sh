#!/usr/bin/env bash
# Same-filesystem copy transaction helpers sourced by vendor.sh.

VENDOR_TRANSACTION=".agents/.vendor-transaction"
VENDOR_TRANSACTION_INITIALIZING="${VENDOR_TRANSACTION}.initializing"
VENDOR_TRANSACTION_VERSION=1
VENDOR_TRANSACTION_PHASE=""
VENDOR_TRANSACTION_MANIFEST_PRESENT=""
VENDOR_TRANSACTION_PRESENCE=()
VENDOR_TRANSACTION_OWNED=""

vendor_transaction_present() {
  [ -e "$VENDOR_TRANSACTION" ] || [ -L "$VENDOR_TRANSACTION" ]
}

vendor_transaction_initializing_present() {
  [ -e "$VENDOR_TRANSACTION_INITIALIZING" ] ||
    [ -L "$VENDOR_TRANSACTION_INITIALIZING" ]
}

vendor_transaction_read_file() {
  local path="$1"
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  LC_ALL=C awk '
    NR == 1 { value = $0 }
    END {
      if (NR != 1) exit 1
      print value
    }
  ' "$path"
}

vendor_transaction_read_presence() {
  local path="$VENDOR_TRANSACTION/original-presence"
  local line skill

  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  VENDOR_TRANSACTION_PRESENCE=()
  {
    IFS= read -r line || return 1
    case "$line" in
    "manifest"$'\t'[01]) VENDOR_TRANSACTION_MANIFEST_PRESENT="${line##*$'\t'}" ;;
    *) return 1 ;;
    esac
    for skill in "${SKILLS[@]}"; do
      IFS= read -r line || return 1
      case "$line" in
      "$skill"$'\t'[01]) VENDOR_TRANSACTION_PRESENCE+=("${line##*$'\t'}") ;;
      *) return 1 ;;
      esac
    done
    ! IFS= read -r line
  } <"$path"
}

vendor_transaction_validate() {
  local version

  [ -d "$VENDOR_TRANSACTION" ] && [ ! -L "$VENDOR_TRANSACTION" ] || return 1
  version="$(vendor_transaction_read_file "$VENDOR_TRANSACTION/version")" || return 1
  [ "$version" = "$VENDOR_TRANSACTION_VERSION" ] || return 1
  VENDOR_TRANSACTION_PHASE="$(vendor_transaction_read_file "$VENDOR_TRANSACTION/phase")" ||
    return 1
  case "$VENDOR_TRANSACTION_PHASE" in
  preparing | staged | commit-started | committed) ;;
  *) return 1 ;;
  esac

  vendor_transaction_read_presence || return 1

  [ -d "$VENDOR_TRANSACTION/stage" ] &&
    [ ! -L "$VENDOR_TRANSACTION/stage" ] &&
    [ -d "$VENDOR_TRANSACTION/backup" ] &&
    [ ! -L "$VENDOR_TRANSACTION/backup" ] || return 1
  case "$VENDOR_TRANSACTION_PHASE" in
  staged | commit-started | committed)
    [ -f "$VENDOR_TRANSACTION/staged-inventory" ] &&
      [ ! -L "$VENDOR_TRANSACTION/staged-inventory" ] || return 1
    ;;
  esac
  case "$VENDOR_TRANSACTION_PHASE" in
  staged)
    [ -f "$VENDOR_TRANSACTION/prepared-manifest" ] &&
      [ ! -L "$VENDOR_TRANSACTION/prepared-manifest" ] || return 1
    ;;
  esac
}

vendor_transaction_write_phase() {
  local phase="$1"
  local temporary="$VENDOR_TRANSACTION/phase.new"
  printf '%s\n' "$phase" >"$temporary" &&
    mv -f "$temporary" "$VENDOR_TRANSACTION/phase"
}

vendor_transaction_remove() {
  rm -rf "$VENDOR_TRANSACTION" || return $?
  if [ "$VENDOR_TRANSACTION_OWNED" = "$VENDOR_TRANSACTION" ]; then
    VENDOR_TRANSACTION_OWNED=""
  fi
}

vendor_transaction_remove_owned() {
  case "$VENDOR_TRANSACTION_OWNED" in
  "$VENDOR_TRANSACTION" | "$VENDOR_TRANSACTION_INITIALIZING") ;;
  *) return 1 ;;
  esac
  rm -rf "$VENDOR_TRANSACTION_OWNED" || return $?
  VENDOR_TRANSACTION_OWNED=""
}

vendor_transaction_restore() {
  local i skill live backup was_present

  vendor_transaction_validate || return 1
  [ "$VENDOR_TRANSACTION_PHASE" = commit-started ] || return 1

  i=0
  for skill in "${SKILLS[@]}"; do
    live=".agents/skills/$skill"
    backup="$VENDOR_TRANSACTION/backup/$skill"
    was_present="${VENDOR_TRANSACTION_PRESENCE[$i]}"
    if [ "$was_present" = 1 ]; then
      if [ -e "$backup" ] || [ -L "$backup" ]; then
        rm -rf "$live" || return $?
        mv "$backup" "$live" || return $?
      elif [ ! -e "$live" ] && [ ! -L "$live" ]; then
        return 1
      fi
    else
      if [ -e "$backup" ] || [ -L "$backup" ]; then
        return 1
      fi
      rm -rf "$live" || return $?
    fi
    i=$((i + 1))
  done

  if [ "$VENDOR_TRANSACTION_MANIFEST_PRESENT" = 1 ]; then
    if [ -e "$VENDOR_TRANSACTION/backup/manifest" ] ||
      [ -L "$VENDOR_TRANSACTION/backup/manifest" ]; then
      rm -f "$MANIFEST" || return $?
      mv "$VENDOR_TRANSACTION/backup/manifest" "$MANIFEST" || return $?
    elif [ ! -e "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then
      return 1
    fi
  else
    if [ -e "$VENDOR_TRANSACTION/backup/manifest" ] ||
      [ -L "$VENDOR_TRANSACTION/backup/manifest" ]; then
      return 1
    fi
    rm -f "$MANIFEST" || return $?
  fi
}

vendor_transaction_finalize_committed() {
  local expected current manifest_inventory_value

  vendor_transaction_validate || return 1
  [ "$VENDOR_TRANSACTION_PHASE" = committed ] || return 1
  expected="$(sed -n '1,$p' "$VENDOR_TRANSACTION/staged-inventory")" || return 1
  current="$(inventory_vendored)" || return 1
  manifest_inventory_value="$(manifest_inventory)" || return 1
  printf '%s\n' "$expected" | validate_inventory || return 1
  printf '%s\n' "$manifest_inventory_value" | validate_inventory || return 1
  [ "$current" = "$expected" ] && [ "$manifest_inventory_value" = "$expected" ] ||
    return 1
  vendor_transaction_remove
}

vendor_transaction_handle_existing() {
  local mode="$1"

  if vendor_transaction_initializing_present; then
    if vendor_transaction_present ||
      [ ! -d "$VENDOR_TRANSACTION_INITIALIZING" ] ||
      [ -L "$VENDOR_TRANSACTION_INITIALIZING" ]; then
      echo "error: invalid vendor transaction initialization state." >&2
      echo "The state was retained at $VENDOR_TRANSACTION_INITIALIZING for manual inspection." >&2
      return 1
    fi
    if [ "$mode" = check ]; then
      echo "error: incomplete vendor transaction initialization detected." >&2
      echo "--check is read-only; run vendor.sh in copy or link mode to remove it." >&2
      return 1
    fi
    rm -rf "$VENDOR_TRANSACTION_INITIALIZING" || {
      echo "error: could not remove abandoned vendor transaction initialization." >&2
      return 1
    }
    echo "Removed an abandoned vendor transaction initialization. Re-run vendor.sh to retry." >&2
    return 1
  fi

  vendor_transaction_present || return 0
  if ! vendor_transaction_validate; then
    echo "error: invalid vendor transaction metadata; refusing recovery." >&2
    echo "The transaction was retained at $VENDOR_TRANSACTION for manual inspection." >&2
    echo "After inspection, move or remove only that transaction directory if the live installation is correct." >&2
    return 1
  fi

  if [ "$mode" = check ]; then
    printf 'error: incomplete vendor updater transaction detected (phase: %s).\n' \
      "$VENDOR_TRANSACTION_PHASE" >&2
    echo "--check is read-only; run vendor.sh in copy or link mode to recover it." >&2
    return 1
  fi

  case "$VENDOR_TRANSACTION_PHASE" in
  preparing | staged)
    vendor_transaction_remove || {
      echo "error: could not remove the abandoned vendor transaction." >&2
      return 1
    }
    echo "Removed an abandoned pre-commit vendor transaction. Re-run vendor.sh to retry." >&2
    return 1
    ;;
  commit-started)
    if ! vendor_transaction_restore; then
      echo "error: could not restore the interrupted vendor transaction." >&2
      echo "The transaction was retained for manual inspection." >&2
      return 1
    fi
    vendor_transaction_remove || {
      echo "error: restored the installation but could not remove transaction artifacts." >&2
      return 1
    }
    echo "Recovered and restored previous installation. Re-run vendor.sh to retry." >&2
    return 1
    ;;
  committed)
    if ! vendor_transaction_finalize_committed; then
      echo "error: could not verify the committed vendor transaction." >&2
      echo "The transaction was retained for manual inspection." >&2
      return 1
    fi
    echo "Recovered a completed vendor transaction. Re-run vendor.sh to continue." >&2
    return 1
    ;;
  esac
}

vendor_transaction_begin() {
  local root="$VENDOR_TRANSACTION_INITIALIZING"
  local temporary="$root/original-presence.new"
  local skill path present

  VENDOR_TRANSACTION_OWNED="$root"
  if ! mkdir "$root"; then
    VENDOR_TRANSACTION_OWNED=""
    return 1
  fi
  if ! mkdir "$root/stage" "$root/backup"; then
    vendor_transaction_remove_owned || true
    return 1
  fi
  if ! printf '%s\n' "$VENDOR_TRANSACTION_VERSION" >"$root/version";
  then
    vendor_transaction_remove_owned || true
    return 1
  fi
  if [ -e "$MANIFEST" ] || [ -L "$MANIFEST" ]; then present=1; else present=0; fi
  printf 'manifest\t%s\n' "$present" >"$temporary" || {
    vendor_transaction_remove_owned || true
    return 1
  }
  for skill in "${SKILLS[@]}"; do
    path=".agents/skills/$skill"
    if [ -e "$path" ] || [ -L "$path" ]; then present=1; else present=0; fi
    printf '%s\t%s\n' "$skill" "$present" >>"$temporary" || {
      vendor_transaction_remove_owned || true
      return 1
    }
  done
  if ! mv -f "$temporary" "$root/original-presence" ||
    ! printf '%s\n' preparing >"$root/phase.new" ||
    ! mv -f "$root/phase.new" "$root/phase" ||
    ! mv "$root" "$VENDOR_TRANSACTION"; then
    vendor_transaction_remove_owned || true
    return 1
  fi
  VENDOR_TRANSACTION_OWNED="$VENDOR_TRANSACTION"
}

vendor_transaction_prepare() {
  local revision="$1"
  local url="$2"
  local source_inventory stage_inventory skill
  local inventory_file="$VENDOR_TRANSACTION/staged-inventory"
  local prepared="$VENDOR_TRANSACTION/prepared-manifest"

  if ! source_inventory="$(inventory_skills "$REPO/skills")" ||
    ! printf '%s\n' "$source_inventory" | validate_inventory; then
    echo "error: source skills could not be inventoried; existing installation is unchanged." >&2
    return 1
  fi
  for skill in "${SKILLS[@]}"; do
    if ! cp -R "$REPO/skills/$skill" "$VENDOR_TRANSACTION/stage/$skill"; then
      echo "error: failed to stage linked-records skills; existing installation is unchanged." >&2
      return 1
    fi
  done
  if ! stage_inventory="$(inventory_skills "$VENDOR_TRANSACTION/stage")" ||
    ! printf '%s\n' "$stage_inventory" | validate_inventory; then
    echo "error: staged skills could not be inventoried; existing installation is unchanged." >&2
    return 1
  fi
  if [ "$source_inventory" != "$stage_inventory" ]; then
    echo "error: staged copy does not match source inventory; existing installation is unchanged." >&2
    return 1
  fi

  printf '%s\n' "$stage_inventory" >"$inventory_file.new" &&
    mv -f "$inventory_file.new" "$inventory_file" || return 1
  {
    echo "# manifest-format: $MANIFEST_FORMAT"
    if [ -n "$url" ]; then echo "# vendored-from: $url"; fi
    if [ -n "$revision" ]; then echo "# revision: $revision"; fi
    echo "# date: $(date +%Y-%m-%d)"
    printf '%s\n' "$stage_inventory"
  } >"$prepared.new" || return 1
  mv -f "$prepared.new" "$prepared" || return 1
  vendor_transaction_write_phase staged
}

vendor_transaction_commit() {
  local expected current i skill live backup was_present

  vendor_transaction_write_phase commit-started || return $?
  vendor_transaction_validate || return 1

  if [ "$VENDOR_TRANSACTION_MANIFEST_PRESENT" = 1 ]; then
    mv "$MANIFEST" "$VENDOR_TRANSACTION/backup/manifest" || return $?
  else
    rm -f "$MANIFEST" || return $?
  fi

  i=0
  for skill in "${SKILLS[@]}"; do
    live=".agents/skills/$skill"
    backup="$VENDOR_TRANSACTION/backup/$skill"
    was_present="${VENDOR_TRANSACTION_PRESENCE[$i]}"
    if [ "$was_present" = 1 ]; then
      mv "$live" "$backup" || return $?
    fi
    mv "$VENDOR_TRANSACTION/stage/$skill" "$live" || return $?
    i=$((i + 1))
  done

  expected="$(sed -n '1,$p' "$VENDOR_TRANSACTION/staged-inventory")" || return 1
  current="$(inventory_vendored)" || return 1
  if [ "$current" != "$expected" ]; then
    echo "error: installed skills do not match the verified staged inventory." >&2
    return 1
  fi
  mv "$VENDOR_TRANSACTION/prepared-manifest" "$MANIFEST" || return $?
  vendor_transaction_write_phase committed || return $?
  vendor_transaction_remove
}

vendor_transaction_signal() {
  local signal="$1"
  local status="$2"
  trap - HUP INT TERM
  if [ -n "$VENDOR_TRANSACTION_OWNED" ]; then
    if [ "$VENDOR_TRANSACTION_OWNED" = "$VENDOR_TRANSACTION" ] &&
      vendor_transaction_validate; then
      case "$VENDOR_TRANSACTION_PHASE" in
      preparing | staged) vendor_transaction_remove || true ;;
      commit-started)
        if vendor_transaction_restore; then
          vendor_transaction_remove || true
        fi
        ;;
      committed) vendor_transaction_finalize_committed || true ;;
      esac
    else
      vendor_transaction_remove_owned || true
    fi
  fi
  printf 'error: vendor transaction interrupted by %s.\n' "$signal" >&2
  exit "$status"
}

vendor_transaction_copy() {
  local revision="$1"
  local url="$2"
  local status

  trap 'vendor_transaction_signal HUP 129' HUP
  trap 'vendor_transaction_signal INT 130' INT
  trap 'vendor_transaction_signal TERM 143' TERM
  if ! vendor_transaction_begin; then
    trap - HUP INT TERM
    echo "error: could not initialize the vendor transaction." >&2
    return 1
  fi

  if vendor_transaction_prepare "$revision" "$url"; then
    :
  else
    status=$?
    if ! vendor_transaction_remove; then
      trap - HUP INT TERM
      echo "error: failed staging and could not remove transaction artifacts." >&2
      return 1
    fi
    trap - HUP INT TERM
    return "$status"
  fi
  if vendor_transaction_commit; then
    trap - HUP INT TERM
    return 0
  else
    status=$?
  fi

  if vendor_transaction_restore; then
    if vendor_transaction_remove; then
      echo "error: vendor transaction failed; restored previous installation." >&2
    else
      echo "error: vendor transaction failed; restored the installation but retained artifacts." >&2
    fi
  else
    echo "error: vendor transaction failed and automatic restoration was incomplete." >&2
    echo "The transaction was retained for recovery on the next mutating invocation." >&2
  fi
  trap - HUP INT TERM
  return "$status"
}
