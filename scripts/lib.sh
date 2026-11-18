#!/usr/bin/env bash
# Shared helpers for the Software Factory scripts. Source this file; don't run it.

# config_get <config.yml> <section.key>
# Reads one value from the factory's flat YAML config: unindented "section:" lines,
# each followed by indented "key: value" lines. Strips a trailing " # comment" and
# surrounding quotes. Prints the value (possibly empty); returns 1 if the key is absent.
config_get() {
  local file=$1 path=$2
  local section=${path%%.*} key=${path#*.}
  awk -v s="$section" -v k="$key" '
    /^[^[:space:]#][^:]*:/ { cur = $0; sub(/:.*/, "", cur); next }
    cur == s && match($0, "^[[:space:]]+" k ":") {
      v = substr($0, RLENGTH + 1)
      sub(/^[[:space:]]+/, "", v)
      sub(/^#.*$/, "", v)
      sub(/[[:space:]]+#.*$/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print v
      found = 1
      exit
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# run_with_timeout <seconds> <command string>
# Runs the command string with bash, killing it after <seconds>.
# A timeout exits 124 (timeout/gtimeout) or 142 (perl fallback, SIGALRM).
run_with_timeout() {
  local secs=$1 cmd=$2
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" bash -c "$cmd"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" bash -c "$cmd"
  else
    perl -e 'alarm shift @ARGV; exec @ARGV or die "exec failed: $!\n"' "$secs" bash -c "$cmd"
  fi
}

is_timeout_code() {
  [ "$1" -eq 124 ] || [ "$1" -eq 142 ]
}
