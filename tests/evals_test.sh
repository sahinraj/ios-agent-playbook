#!/usr/bin/env bash
# Checks the eval task format and the scorer against known good and bad answers.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures/evals"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

count=0
for task in "$ROOT"/evals/tasks/*/; do
  count=$((count + 1))
  [[ -s "$task/prompt.md" ]] || fail "missing prompt: $task"
  [[ -s "$task/checks.txt" ]] || fail "missing checks: $task"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^[+-]\ [^$'\t']+$'\t'.+ ]] || fail "bad check line in $task: $line"
    # Every pattern must be a valid extended regex. grep exits 2 on a bad one.
    pattern="${line%%$'\t'*}"
    pattern="${pattern:2}"
    status=0
    printf '' | grep -Eq -- "$pattern" || status=$?
    [[ "$status" -le 1 ]] || fail "invalid regex in $task: $pattern"
  done <"$task/checks.txt"
done
[[ "$count" -ge 10 ]] || fail "expected at least 10 tasks, found $count"

out="$("$ROOT/evals/score.sh" "$FIXTURES/bad" "$FIXTURES/good")"
grep -q '| 01-shipped-schema-change | 0/6 | 6/6 |' <<<"$out" || fail "unexpected scores: $out"
grep -q '| 03-trivial-rename | n/a | 5/5 |' <<<"$out" || fail "unexpected scores: $out"
grep -q '| 07-cannot-build | 0/5 | n/a |' <<<"$out" || fail "unexpected scores: $out"
grep -q '| \*\*Total\*\* | \*\*0/11 (0%)\*\* | \*\*11/11 (100%)\*\* |' <<<"$out" || fail "unexpected totals: $out"

printf 'eval tests passed\n'
