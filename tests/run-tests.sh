#!/usr/bin/env bash
# Tests for the Software Factory scripts. Builds throwaway git repos in a temp folder.
# Usage: tests/run-tests.sh
set -uo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scripts="$root/scripts"
# shellcheck source=../scripts/lib.sh
. "$scripts/lib.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
contains() { # contains <name> <file> <text>
  if grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1 ($2 lacks [$3])"; fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

new_repo() { # new_repo <dir>: a tiny Node project with one passing test
  mkdir -p "$1/src" "$1/test"
  cd "$1" || exit 1
  git init -q -b main
  git config user.email factory-test@example.com
  git config user.name "Factory Test"
  cat >src/add.js <<'EOF'
module.exports = (a, b) => a + b;
EOF
  cat >test/add.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const add = require('../src/add');
test('adds', () => assert.strictEqual(add(2, 3), 5));
EOF
  git add -A
  git commit -qm init
}

write_config() { # write_config <file> <test cmd> [timeout]
  mkdir -p "$(dirname "$1")"
  cat >"$1" <<EOF
# comment line
project:
  name: demo   # trailing comment
  notes: "quoted value"

commands:
  test: $2
  test_one: node --test {file}
  lint:
  typecheck: # nothing here
  build: 'true'
  coverage:

tests:
  patterns: "test/** **/*.test.js"

limits:
  command_timeout_sec: ${3:-60}

review:
  external: off
EOF
}

echo "config_get"
cfg="$tmp/cfg.yml"
write_config "$cfg" "node --test"
check "reads a plain value" "node --test" "$(config_get "$cfg" commands.test)"
check "strips a trailing comment" "demo" "$(config_get "$cfg" project.name)"
check "strips double quotes" "quoted value" "$(config_get "$cfg" project.notes)"
check "strips single quotes" "true" "$(config_get "$cfg" commands.build)"
check "keeps {file} placeholder" "node --test {file}" "$(config_get "$cfg" commands.test_one)"
check "empty value is empty" "" "$(config_get "$cfg" commands.lint)"
check "comment-only value is empty" "" "$(config_get "$cfg" commands.typecheck)"
check "keeps globs intact" "test/** **/*.test.js" "$(config_get "$cfg" tests.patterns)"
config_get "$cfg" commands.nope >/dev/null
check "missing key returns 1" "1" "$?"
config_get "$cfg" project.test >/dev/null
check "key is scoped to its section" "1" "$?"

echo "verify.sh"
repo="$tmp/verify"
new_repo "$repo"
write_config .factory/config.yml "node --test"
bash "$scripts/verify.sh" .factory/config.yml .factory/run/test-report.md >/dev/null
check "passing project exits 0" "0" "$?"
contains "report says PASS" .factory/run/test-report.md "Result: **PASS**"
contains "unset check is skipped" .factory/run/test-report.md "| lint | skipped (not set) | | |"
contains "full log is saved" .factory/run/logs/test.log "pass 1"

cat >test/add.test.js <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const add = require('../src/add');
test('adds', () => assert.strictEqual(add(2, 3), 6));
EOF
bash "$scripts/verify.sh" .factory/config.yml .factory/run/test-report.md >/dev/null
check "failing test exits 1" "1" "$?"
contains "report says FAIL" .factory/run/test-report.md "Result: **FAIL**"
contains "report has a failures section" .factory/run/test-report.md "### test"
contains "report points to the log" .factory/run/test-report.md 'Full log: `logs/test.log`'
git checkout -q -- test/add.test.js

write_config .factory/config.yml "sleep 5" 1
bash "$scripts/verify.sh" .factory/config.yml .factory/run/test-report.md >/dev/null
check "slow check exits 1" "1" "$?"
contains "report says it timed out" .factory/run/test-report.md "timed out after 1s"

printf 'commands:\n  test:\n' >.factory/empty.yml
bash "$scripts/verify.sh" .factory/empty.yml .factory/run/test-report.md >/dev/null 2>&1
check "no configured checks exits 1" "1" "$?"
bash "$scripts/verify.sh" .factory/missing.yml .factory/run/test-report.md >/dev/null 2>&1
check "missing config exits 2" "2" "$?"

echo "guard-tests.sh"
repo="$tmp/guard"
new_repo "$repo"
write_config .factory/config.yml "node --test"
cat >test/sub.test.js <<'EOF'
// test writer's new test for this step
EOF
git add -A && git commit -qm "test: step 1"
test_ref=$(git rev-parse HEAD)

echo "module.exports = (a, b) => a + b; // tidied" >src/add.js
bash "$scripts/guard-tests.sh" .factory/config.yml "$test_ref" >/dev/null
check "code-only change exits 0" "0" "$?"

echo "// weakened" >test/sub.test.js
out=$(bash "$scripts/guard-tests.sh" .factory/config.yml "$test_ref")
check "edited step test exits 3" "3" "$?"
check "edited step test is restored" "// test writer's new test for this step" "$(cat test/sub.test.js)"
case $out in *test/sub.test.js*) ok "output names the file" ;; *) bad "output names the file ($out)" ;; esac

echo "// weakened" >>test/add.test.js
bash "$scripts/guard-tests.sh" .factory/config.yml "$test_ref" >/dev/null
check "edited older test (by pattern) exits 3" "3" "$?"
git diff --quiet -- test/add.test.js
check "older test is restored" "0" "$?"

rm test/sub.test.js
bash "$scripts/guard-tests.sh" .factory/config.yml "$test_ref" >/dev/null
check "deleted test exits 3" "3" "$?"
[ -f test/sub.test.js ]
check "deleted test is back" "0" "$?"

echo "// builder's extra test" >test/extra.test.js
git add test/extra.test.js
bash "$scripts/guard-tests.sh" .factory/config.yml "$test_ref" >/dev/null
check "new test file is allowed" "0" "$?"
[ -f test/extra.test.js ]
check "new test file is kept" "0" "$?"
git rm -q --cached test/extra.test.js && rm test/extra.test.js

git add -A && git commit -qm "feat: step 1"
echo "// note" >>src/add.js
git add -A && git commit -qm "feat: step 2 (no tests)"
echo "// weakened" >>test/add.test.js
bash "$scripts/guard-tests.sh" .factory/config.yml HEAD --patterns-only >/dev/null
check "--patterns-only still protects tests" "3" "$?"
echo "// more" >>src/add.js
bash "$scripts/guard-tests.sh" .factory/config.yml HEAD --patterns-only >/dev/null
check "--patterns-only ignores code changes" "0" "$?"
git checkout -q -- src/add.js

bash "$scripts/guard-tests.sh" .factory/config.yml not-a-ref >/dev/null 2>&1
check "bad ref exits 2" "2" "$?"

echo "external-review.sh"
repo="$tmp/external"
new_repo "$repo"
base=$(git rev-parse HEAD)
write_config .factory/config.yml "node --test"
echo "# Spec: demo" >spec.md
echo "module.exports = (a, b) => a - b;" >src/add.js
git add -A && git commit -qm "change"

bash "$scripts/external-review.sh" .factory/config.yml "$base" spec.md out.md >/dev/null
check "review.external off exits 4" "4" "$?"
contains "skip reason is written" out.md "turned off"

stubs="$tmp/stubs"
mkdir -p "$stubs"
gitdir=$(dirname "$(command -v git)")
sed -i.bak 's/external: off/external: auto/' .factory/config.yml
PATH="$stubs:$gitdir:/usr/bin:/bin" bash "$scripts/external-review.sh" .factory/config.yml "$base" spec.md out.md >/dev/null
check "auto with no tool exits 4" "4" "$?"

cat >"$stubs/gemini" <<'EOF'
#!/bin/bash
# fake gemini: echo the prompt flag and prove the diff arrived on stdin
[ "$1" = "-p" ] || { echo "expected -p" >&2; exit 9; }
input=$(cat)
case $input in *"a - b"*) echo "- [major] src/add.js:1 - subtracts instead of adds - wrong sums - use +" ;; *) echo "no diff on stdin" >&2; exit 8 ;; esac
EOF
chmod +x "$stubs/gemini"
PATH="$stubs:$gitdir:/usr/bin:/bin" bash "$scripts/external-review.sh" .factory/config.yml "$base" spec.md out.md >/dev/null
check "gemini review exits 0" "0" "$?"
contains "review names the tool" out.md "second opinion (gemini)"
contains "review has the finding" out.md "subtracts instead of adds"

printf '#!/bin/bash\necho "quota exceeded" >&2\nexit 1\n' >"$stubs/gemini"
PATH="$stubs:$gitdir:/usr/bin:/bin" bash "$scripts/external-review.sh" .factory/config.yml "$base" spec.md out.md >/dev/null
check "failing tool exits 1" "1" "$?"
contains "failure details are written" out.md "quota exceeded"

PATH="$stubs:$gitdir:/usr/bin:/bin" bash "$scripts/external-review.sh" .factory/config.yml HEAD spec.md out.md >/dev/null
check "no diff exits 4" "4" "$?"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
