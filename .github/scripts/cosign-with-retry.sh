#!/usr/bin/env bash
# Run cosign with retries for transient Rekor/network failures.
#
# The public Rekor instance occasionally returns errors such as
#   Post "https://rekor.sigstore.dev/api/v1/log/entries": ... giving up after 2 attempt(s)
# Retry only those transient errors, with exponential backoff. A conflict
# (entry already in the transparency log) can optionally be treated as success
# so workflow re-runs stay idempotent.
#
# Usage: cosign_with_retry <logfile> <tolerate-conflict:true|false> <cosign args...>
cosign_with_retry() {
  local log=$1 tolerate_conflict=$2
  shift 2
  local attempt=1 max_attempts=5 delay=15
  local transient='giving up after|i/o timeout|context deadline exceeded|TLS handshake timeout|connection reset|unexpected EOF|no such host|server misbehaving|502 Bad Gateway|503 Service Unavailable|504 Gateway Timeout|429 Too Many Requests'
  while :; do
    if cosign "$@" 2>"$log"; then
      return 0
    fi
    if [ "$tolerate_conflict" = "true" ] && grep -qE "createLogEntryConflict|HTTP 409|409 Conflict|status code 409" "$log"; then
      echo "Already present in transparency log: $*" >&2
      return 0
    fi
    if ! grep -qE "$transient" "$log"; then
      cat "$log" >&2
      return 1
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "cosign $* failed after $attempt attempt(s)" >&2
      cat "$log" >&2
      return 1
    fi
    echo "cosign attempt $attempt/$max_attempts failed (transient); retrying in ${delay}s" >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}
