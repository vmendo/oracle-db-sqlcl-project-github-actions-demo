#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <sqlcl-verify-log>" >&2
  exit 2
fi

log_file="$1"
if [[ ! -f "$log_file" ]]; then
  echo "SQLcl verify log not found: $log_file" >&2
  exit 2
fi

clean_log="$(mktemp)"
perl -pe 's/\e\[[0-9;]*m//g' "$log_file" > "$clean_log"

error_count="$(awk '/Errors:/ { print $2; found = 1; exit } END { if (!found) exit 1 }' "$clean_log" || true)"

if [[ -z "$error_count" ]]; then
  echo "SQLcl verify output did not include an Errors summary." >&2
  cat "$clean_log" >&2
  exit 1
fi

if [[ ! "$error_count" =~ ^[0-9]+$ ]]; then
  echo "Unable to parse SQLcl verify error count: $error_count" >&2
  cat "$clean_log" >&2
  exit 1
fi

if (( error_count > 0 )); then
  echo "SQLcl Project verify reported $error_count error(s)." >&2
  cat "$clean_log" >&2
  exit 1
fi

echo "SQLcl Project verify reported zero errors."
