#!/usr/bin/env bash
# Keeps the builder from changing tests. Any protected test file that was modified
# or deleted since <ref> is restored to its <ref> version.
#
# A file is protected when:
#   - <ref> (the test writer's commit for this step) added or changed it, or
#   - it matches tests.patterns in the config (space-separated git pathspec globs).
# New test files the builder adds are left alone; only changes to existing tests count.
#
# Usage: guard-tests.sh <config.yml> <ref> [--patterns-only]
#   --patterns-only  protect only files matching tests.patterns (use when the test
#                    writer made no commit for this step and <ref> is just HEAD)
# Exit codes: 0 no protected file changed, 3 protected files changed and were restored,
#             2 usage error.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$here/lib.sh"

usage() {
  echo "usage: guard-tests.sh <config.yml> <ref> [--patterns-only]" >&2
  exit 2
}
[ $# -ge 2 ] && [ $# -le 3 ] || usage
config=$1
ref=$2
mode=${3:-}
[ -z "$mode" ] || [ "$mode" = --patterns-only ] || usage
[ -f "$config" ] || { echo "config not found: $config" >&2; exit 2; }
git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || { echo "not a commit: $ref" >&2; exit 2; }

# Tracked files that differ from <ref>, in the index or the working tree.
changed=$(git diff --name-only "$ref" --)
[ -n "$changed" ] || exit 0

protected=""
if [ "$mode" != --patterns-only ]; then
  protected=$(git diff-tree --no-commit-id --name-only -r "$ref")
fi

by_pattern=""
patterns=$(config_get "$config" tests.patterns || true)
if [ -n "$patterns" ]; then
  set -f # keep the globs away from the shell; git expands them
  specs=()
  for p in $patterns; do specs+=(":(glob)$p"); done
  set +f
  by_pattern=$(git diff --name-only "$ref" -- "${specs[@]}")
fi

hits=$(
  {
    comm -12 <(printf '%s\n' "$changed" | sort -u) <(printf '%s\n' "$protected" | sort -u)
    printf '%s\n' "$by_pattern"
  } | sed '/^$/d' | sort -u
)

restored=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if git cat-file -e "$ref:$f" 2>/dev/null; then
    git checkout "$ref" -- "$f"
    restored+=("$f")
  fi
done <<<"$hits"

[ ${#restored[@]} -gt 0 ] || exit 0

echo "These test files were changed after the test writer's commit and have been restored to $(git rev-parse --short "$ref"):"
printf '  %s\n' "${restored[@]}"
exit 3
