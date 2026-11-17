#!/usr/bin/env bash
# Runs docs/install.sh against this local checkout instead of GitHub.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# The bootstrap clones a git repository. Build a throwaway one from the
# working tree so uncommitted changes are tested too.
SOURCE="$TEST_ROOT/source"
mkdir -p "$SOURCE"
(cd "$ROOT" && tar --exclude .git --exclude 'evals/results' -cf - .) | (cd "$SOURCE" && tar -xf -)
git -C "$SOURCE" init --quiet
git -C "$SOURCE" config user.email "test@example.com"
git -C "$SOURCE" config user.name "Test"
git -C "$SOURCE" config commit.gpgsign false
git -C "$SOURCE" add -A
git -C "$SOURCE" commit --quiet -m "snapshot"

export HOME="$TEST_ROOT/home"
export IOS_PLAYBOOK_REPO="$SOURCE"
export IOS_PLAYBOOK_HOME="$TEST_ROOT/checkout"
mkdir -p "$HOME"

out="$(bash "$ROOT/docs/install.sh")"
grep -q "curl -fsSL .* | bash -s -- project" <<<"$out" || fail "bootstrap should print the curl project hint"
[[ -L "$HOME/.claude/skills/ios-playbook" ]] || fail "Claude skill not linked"
[[ -L "$HOME/.copilot/skills/ios-playbook" ]] || fail "Copilot skill not linked"
[[ -L "$HOME/.copilot/agents/ios-playbook.agent.md" ]] || fail "agent not linked"
[[ -f "$HOME/.claude/skills/ios-playbook/SKILL.md" ]] || fail "link does not resolve"

# Second run updates in place and stays idempotent.
bash "$ROOT/docs/install.sh" personal >/dev/null

# Arguments are passed through to install.sh.
project="$TEST_ROOT/project"
mkdir -p "$project"
bash "$ROOT/docs/install.sh" project "$project" --claude >/dev/null
[[ -f "$project/.claude/skills/ios-playbook/SKILL.md" ]] || fail "project install through the bootstrap failed"

mkdir -p "$TEST_ROOT/blocked"
if IOS_PLAYBOOK_HOME="$TEST_ROOT/blocked" bash "$ROOT/docs/install.sh" >/dev/null 2>&1; then
  fail "expected refusal for a non-git destination"
fi

printf 'bootstrap tests passed\n'
