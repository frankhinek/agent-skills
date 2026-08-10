#!/usr/bin/env bash
# Canonical provenance and the sole network-capable remote query for vendor.sh.

PROVENANCE_PREFIX="https://github.com/"

provenance_path_valid() {
  local path="$1"
  local owner repository

  case "$path" in
  */*) ;;
  *) return 1 ;;
  esac
  owner="${path%%/*}"
  repository="${path#*/}"
  case "$repository" in
  */*) return 1 ;;
  esac
  case "$owner" in
  "" | "." | ".." | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  case "$repository" in
  "" | "." | ".." | *[!A-Za-z0-9._-]*) return 1 ;;
  esac
}

# Accept the repository's common GitHub clone forms only as source identifiers.
# The returned value is always non-secret canonical HTTPS provenance.
canonicalize_source_provenance() {
  local source="$1"
  local path canonical

  case "$source" in
  "$PROVENANCE_PREFIX"*) path="${source#"$PROVENANCE_PREFIX"}" ;;
  git@github.com:*) path="${source#git@github.com:}" ;;
  *) return 1 ;;
  esac
  case "$path" in
  *.git) path="${path%.git}" ;;
  esac
  provenance_path_valid "$path" || return 1
  canonical="$PROVENANCE_PREFIX$path"
  printf '%s\n' "$canonical"
}

canonical_provenance_valid() {
  local value="$1"
  local canonical

  canonical="$(canonicalize_source_provenance "$value")" || return 1
  [ "$canonical" = "$value" ]
}

# Read the stored origin without applying url.*.insteadOf rewrites. Status 1
# means no origin; status 2 means duplicate, multiline, or unreadable metadata.
source_origin_value() {
  local source_repo="$1"

  git -C "$source_repo" config --local --get-all remote.origin.url 2>/dev/null |
    LC_ALL=C awk '
      { lines++; value = $0 }
      END {
        if (lines == 0) exit 1
        if (lines != 1) exit 2
        print value
      }
    '
}

# Manifest provenance is stricter than source normalization: only the exact
# canonical form is executable. Any other present value is invalid (status 2).
manifest_provenance_value() {
  local value

  if value="$(manifest_strict_field_value vendored-from)"; then
    :
  else
    return $?
  fi
  canonical_provenance_valid "$value" || return 2
  printf '%s\n' "$value"
}

# Query only validated provenance. Excluding repository, global, and system Git
# configuration prevents url.*.insteadOf from redirecting the approved host.
provenance_remote_head() {
  local url="$1"

  canonical_provenance_valid "$url" || return 2
  (
    unset GIT_COMMON_DIR GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_WORK_TREE
    unset GIT_PROXY_SSL_CAINFO GIT_PROXY_SSL_CERT GIT_PROXY_SSL_CERT_PASSWORD_PROTECTED
    unset GIT_PROXY_SSL_KEY GIT_SSL_CAINFO GIT_SSL_CAPATH GIT_SSL_CERT
    unset GIT_SSL_CERT_PASSWORD_PROTECTED GIT_SSL_CIPHER_LIST GIT_SSL_KEY
    unset GIT_SSL_NO_VERIFY GIT_SSL_VERSION
    unset NETRC
    export CURL_HOME=/dev/null
    export GIT_ALLOW_PROTOCOL=https
    export GIT_ASKPASS=/usr/bin/false
    export GIT_CONFIG_COUNT=0
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_SYSTEM=/dev/null
    export GIT_DIR=/dev/null
    export GIT_TERMINAL_PROMPT=0
    export GCM_INTERACTIVE=never
    export HOME=/dev/null
    export SSH_ASKPASS=/usr/bin/false
    export XDG_CONFIG_HOME=/dev/null
    git \
      -c protocol.allow=never \
      -c protocol.https.allow=always \
      -c credential.helper= \
      ls-remote "$url" HEAD
  )
}
