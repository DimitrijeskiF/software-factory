#!/usr/bin/env bash
# Second-opinion review from a model made by another company: OpenAI Codex or
# Google Gemini, through their command-line tools. Optional and best effort.
#
# Setting review.external in the config: auto (codex, else gemini, else skip),
# codex, gemini, or off.
#   codex  runs `codex exec --sandbox read-only` in the repo and reads the diff itself.
#   gemini gets the spec and the diff on stdin with no tools (`gemini -p`).
#
# Usage: external-review.sh <config.yml> <base-ref> <spec.md> <out.md>
# Exit codes: 0 review written, 4 skipped (reason in <out.md>), 1 the tool failed
#             (details in <out.md>), 2 usage error.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

if [ $# -ne 4 ]; then
  echo "usage: external-review.sh <config.yml> <base-ref> <spec.md> <out.md>" >&2
  exit 2
fi
config=$1
base=$2
spec=$3
out=$4
[ -f "$config" ] || { echo "config not found: $config" >&2; exit 2; }
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { echo "not a commit: $base" >&2; exit 2; }

skip() {
  printf '# Review: second opinion\n\nSkipped: %s\n' "$1" >"$out"
  echo "external review skipped: $1"
  exit 4
}

mode=$(config_get "$config" review.external || true)
mode=${mode:-auto}
tool=""
case $mode in
  off) skip "turned off in the config (review.external: off)" ;;
  codex | gemini)
    command -v "$mode" >/dev/null 2>&1 || skip "review.external is $mode, but the $mode command isn't installed"
    tool=$mode
    ;;
  auto)
    if command -v codex >/dev/null 2>&1; then
      tool=codex
    elif command -v gemini >/dev/null 2>&1; then
      tool=gemini
    else
      skip "neither the codex nor the gemini command is installed"
    fi
    ;;
  *)
    echo "unknown review.external value: $mode (use auto, codex, gemini or off)" >&2
    exit 2
    ;;
esac

if git diff --quiet "$base"...HEAD --; then
  skip "no changes between $(git rev-parse --short "$base") and HEAD"
fi

instructions='You are a senior engineer reviewing a code change before it is merged.
Report only real problems: bugs, wrong logic, unhandled errors and edge cases, security
issues, missing or weak tests, and places where the change does not do what the spec asks.
Skip style preferences and anything you cannot point to in the code.
For each problem write one Markdown bullet in this exact shape:
- [blocker|major|minor] path/to/file:line - what is wrong - why it matters - suggested fix
If you find nothing, write exactly: No findings.
Do not modify any files.'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export FACTORY_PROMPT FACTORY_INPUT

case $tool in
  codex)
    FACTORY_PROMPT="$instructions

The change is the diff between $base and HEAD in this git repository. Read it with:
git diff $base...HEAD
The spec it implements is in: $spec"
    FACTORY_INPUT=/dev/null
    cmd='codex exec --sandbox read-only "$FACTORY_PROMPT" </dev/null'
    ;;
  gemini)
    FACTORY_INPUT="$work/input.md"
    {
      printf '## Spec\n\n'
      if [ -f "$spec" ]; then cat "$spec"; else printf '(no spec file at %s)\n' "$spec"; fi
      printf '\n\n## Diff (%s...HEAD)\n\n```diff\n' "$(git rev-parse --short "$base")"
      git diff "$base"...HEAD --
      printf '```\n'
    } >"$FACTORY_INPUT"
    FACTORY_PROMPT="$instructions"
    cmd='gemini -p "$FACTORY_PROMPT" <"$FACTORY_INPUT"'
    ;;
esac

timeout_sec=600
run_with_timeout "$timeout_sec" "$cmd" >"$work/stdout" 2>"$work/stderr"
code=$?

if [ "$code" -ne 0 ] || [ ! -s "$work/stdout" ]; then
  {
    printf '# Review: second opinion (%s)\n\n' "$tool"
    if is_timeout_code "$code"; then
      printf 'Failed: timed out after %ss.\n\n' "$timeout_sec"
    else
      printf 'Failed: %s exited with code %s.\n\n' "$tool" "$code"
    fi
    printf 'Last lines of its error output:\n\n```text\n%s\n```\n' "$(tail -n 30 "$work/stderr")"
  } >"$out"
  echo "external review failed ($tool, exit $code); details in $out"
  exit 1
fi

{
  printf '# Review: second opinion (%s)\n\n' "$tool"
  cat "$work/stdout"
} >"$out"
echo "external review written by $tool: $out"
