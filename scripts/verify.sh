#!/usr/bin/env bash
# Runs the project's checks listed under "commands:" in .factory/config.yml
# (test, lint, typecheck, build, coverage) and writes a Markdown report.
# Full output of every check is saved next to the report in logs/<check>.log.
#
# Usage: verify.sh <config.yml> <report.md>
# Exit codes: 0 every configured check passed, 1 at least one check failed,
#             2 usage or config error.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

if [ $# -ne 2 ]; then
  echo "usage: verify.sh <config.yml> <report.md>" >&2
  exit 2
fi
config=$1
report=$2
if [ ! -f "$config" ]; then
  echo "config not found: $config" >&2
  exit 2
fi

timeout_sec=$(config_get "$config" limits.command_timeout_sec || true)
case $timeout_sec in '' | *[!0-9]*) timeout_sec=900 ;; esac

report_dir=$(dirname "$report")
log_dir="$report_dir/logs"
mkdir -p "$log_dir"

tail_lines=80
overall=PASS
ran=0
rows=""
commands_list=""
failures=""

for check in test lint typecheck build coverage; do
  cmd=$(config_get "$config" "commands.$check" || true)
  if [ -z "$cmd" ]; then
    rows+="| $check | skipped (not set) | | |"$'\n'
    echo "$check: skipped (not set)"
    continue
  fi
  ran=$((ran + 1))
  commands_list+="- $check: \`$cmd\`"$'\n'
  log="$log_dir/$check.log"
  start=$(date +%s)
  run_with_timeout "$timeout_sec" "$cmd" >"$log" 2>&1
  code=$?
  secs=$(($(date +%s) - start))
  if [ "$code" -eq 0 ]; then
    result=pass
  else
    overall=FAIL
    if is_timeout_code "$code"; then
      result="FAIL (timed out after ${timeout_sec}s)"
    else
      result=FAIL
    fi
    total=$(wc -l <"$log" | tr -d ' ')
    failures+="### $check"$'\n\n'
    failures+="Command: \`$cmd\` · exit $code · last $tail_lines of $total lines. Full log: \`logs/$check.log\`"$'\n\n'
    failures+='```text'$'\n'"$(tail -n "$tail_lines" "$log")"$'\n''```'$'\n\n'
  fi
  rows+="| $check | $result | $code | $secs |"$'\n'
  echo "$check: $result (exit $code, ${secs}s)"
done

if [ "$ran" -eq 0 ]; then
  echo "no checks configured under commands: in $config" >&2
  overall=FAIL
fi

{
  echo "# Verify report"
  echo
  echo "Result: **$overall**"
  echo "Run at: $(date '+%Y-%m-%d %H:%M:%S') · commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo
  echo "| Check | Result | Exit | Seconds |"
  echo "|---|---|---|---|"
  printf '%s' "$rows"
  echo
  if [ "$ran" -eq 0 ]; then
    echo "No checks are configured. Add commands under \`commands:\` in \`$config\`, or run /factory-setup."
    echo
  fi
  if [ -n "$commands_list" ]; then
    echo "## Commands"
    echo
    printf '%s' "$commands_list"
    echo
  fi
  if [ -n "$failures" ]; then
    echo "## Failures"
    echo
    printf '%s' "$failures"
  fi
} >"$report"

echo "Result: $overall · report: $report"
[ "$overall" = PASS ]
