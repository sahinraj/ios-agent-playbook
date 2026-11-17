#!/usr/bin/env bash
# Exercises every installer command against a throwaway HOME and sample repos.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

assert_link() {
  [[ -L "$1" ]] || fail "expected a symlink: $1"
}

assert_absent() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "expected path to be absent: $1"
}

block_count() {
  grep -c '<!-- ios-playbook:start -->' "$1" || true
}

HOME="$TEST_ROOT/home"
export HOME
mkdir -p "$HOME"

"$ROOT/install.sh" verify >/dev/null

# --- project install, Copilot only (detected from an existing instructions file)
copilot_repo="$TEST_ROOT/copilot-repo"
mkdir -p "$copilot_repo/.github"
printf '# Existing project guidance\n' > "$copilot_repo/.github/copilot-instructions.md"

"$ROOT/install.sh" project "$copilot_repo" >/dev/null
"$ROOT/install.sh" project "$copilot_repo" >/dev/null   # idempotent

assert_file "$copilot_repo/.github/skills/ios-playbook/SKILL.md"
assert_file "$copilot_repo/.github/skills/ios-playbook/scripts/project-facts.sh"
assert_file "$copilot_repo/.github/agents/ios-playbook.agent.md"
assert_file "$copilot_repo/.github/instructions/ios-playbook.instructions.md"
assert_absent "$copilot_repo/.claude"
assert_absent "$copilot_repo/CLAUDE.md"
[[ "$(block_count "$copilot_repo/.github/copilot-instructions.md")" == 1 ]] || fail "managed block should occur once"
grep -q '# Existing project guidance' "$copilot_repo/.github/copilot-instructions.md" || fail "existing guidance was not preserved"
[[ -x "$copilot_repo/.github/skills/ios-playbook/scripts/diff-audit.sh" ]] || fail "copied scripts should stay executable"

"$ROOT/install.sh" uninstall-project "$copilot_repo" >/dev/null
assert_absent "$copilot_repo/.github/skills/ios-playbook"
assert_absent "$copilot_repo/.github/agents/ios-playbook.agent.md"
assert_absent "$copilot_repo/.github/instructions/ios-playbook.instructions.md"
grep -q '# Existing project guidance' "$copilot_repo/.github/copilot-instructions.md" || fail "uninstall removed existing guidance"
[[ "$(block_count "$copilot_repo/.github/copilot-instructions.md")" == 0 ]] || fail "managed block should be gone"

# --- project install, Claude only (detected from CLAUDE.md)
claude_repo="$TEST_ROOT/claude-repo"
mkdir -p "$claude_repo"
printf '# My app\n\nHouse rules.\n' > "$claude_repo/CLAUDE.md"

"$ROOT/install.sh" project "$claude_repo" >/dev/null
"$ROOT/install.sh" project "$claude_repo" >/dev/null

assert_file "$claude_repo/.claude/skills/ios-playbook/SKILL.md"
assert_file "$claude_repo/.claude/skills/ios-playbook/references/handoff.md"
assert_absent "$claude_repo/.github"
[[ "$(block_count "$claude_repo/CLAUDE.md")" == 1 ]] || fail "CLAUDE.md block should occur once"
grep -q 'House rules.' "$claude_repo/CLAUDE.md" || fail "CLAUDE.md content was not preserved"

"$ROOT/install.sh" uninstall-project "$claude_repo" >/dev/null
assert_absent "$claude_repo/.claude/skills/ios-playbook"
grep -q 'House rules.' "$claude_repo/CLAUDE.md" || fail "uninstall removed CLAUDE.md content"
[[ "$(block_count "$claude_repo/CLAUDE.md")" == 0 ]] || fail "CLAUDE.md block should be gone"

# --- project install, AGENTS.md is used when it is the only instruction file
agents_repo="$TEST_ROOT/agents-repo"
mkdir -p "$agents_repo"
printf '# Agents\n' > "$agents_repo/AGENTS.md"
"$ROOT/install.sh" project "$agents_repo" --claude >/dev/null
[[ "$(block_count "$agents_repo/AGENTS.md")" == 1 ]] || fail "AGENTS.md should get the block"
assert_absent "$agents_repo/CLAUDE.md"
"$ROOT/install.sh" uninstall-project "$agents_repo" >/dev/null
[[ "$(block_count "$agents_repo/AGENTS.md")" == 0 ]] || fail "AGENTS.md block should be gone"

# --- project install into an empty repo installs for both tools
both_repo="$TEST_ROOT/both-repo"
mkdir -p "$both_repo"
"$ROOT/install.sh" project "$both_repo" >/dev/null
assert_file "$both_repo/.claude/skills/ios-playbook/SKILL.md"
assert_file "$both_repo/.github/skills/ios-playbook/SKILL.md"
assert_file "$both_repo/CLAUDE.md"
assert_file "$both_repo/.github/copilot-instructions.md"
"$ROOT/install.sh" verify "$both_repo" >/dev/null
mkdir -p "$both_repo/.playbook"
printf 'mine\n' > "$both_repo/.playbook/repo-map.md"
"$ROOT/install.sh" uninstall-project "$both_repo" >/dev/null
assert_absent "$both_repo/.claude/skills/ios-playbook"
assert_absent "$both_repo/.github/skills/ios-playbook"
assert_absent "$both_repo/CLAUDE.md"
assert_absent "$both_repo/.github/copilot-instructions.md"
assert_file "$both_repo/.playbook/repo-map.md"

# --- a folder the installer did not create is never overwritten without --force
foreign_repo="$TEST_ROOT/foreign-repo"
mkdir -p "$foreign_repo/.claude/skills/ios-playbook"
printf 'my own skill\n' > "$foreign_repo/.claude/skills/ios-playbook/SKILL.md"
if "$ROOT/install.sh" project "$foreign_repo" --claude >/dev/null 2>&1; then
  fail "expected refusal when a foreign folder is in the way"
fi
grep -q 'my own skill' "$foreign_repo/.claude/skills/ios-playbook/SKILL.md" || fail "foreign folder was modified"
"$ROOT/install.sh" project "$foreign_repo" --claude --force >/dev/null 2>&1
grep -q 'name: ios-playbook' "$foreign_repo/.claude/skills/ios-playbook/SKILL.md" || fail "--force did not install"
found_backup=0
for candidate in "$foreign_repo/.claude/skills/"ios-playbook.backup-*; do
  if [[ -e "$candidate" ]]; then found_backup=1; fi
done
[[ "$found_backup" == 1 ]] || fail "--force did not keep a backup"

# --- personal install: with no tool folders it installs for both, as symlinks
"$ROOT/install.sh" personal >/dev/null
assert_link "$HOME/.claude/skills/ios-playbook"
assert_link "$HOME/.copilot/skills/ios-playbook"
assert_link "$HOME/.copilot/agents/ios-playbook.agent.md"
assert_file "$HOME/.claude/skills/ios-playbook/SKILL.md"
"$ROOT/install.sh" personal >/dev/null   # idempotent
"$ROOT/install.sh" uninstall-personal >/dev/null
assert_absent "$HOME/.claude/skills/ios-playbook"
assert_absent "$HOME/.copilot/skills/ios-playbook"
assert_absent "$HOME/.copilot/agents/ios-playbook.agent.md"

# --- personal install: only the tool whose folder exists
rm -rf "$HOME/.copilot"
mkdir -p "$HOME/.claude"
"$ROOT/install.sh" personal >/dev/null
assert_link "$HOME/.claude/skills/ios-playbook"
assert_absent "$HOME/.copilot/skills/ios-playbook"
"$ROOT/install.sh" uninstall-personal >/dev/null

# --- personal install: explicit flags and copy mode, then switching back to links
"$ROOT/install.sh" personal --copy --claude --copilot >/dev/null
assert_file "$HOME/.claude/skills/ios-playbook/SKILL.md"
assert_file "$HOME/.claude/skills/ios-playbook/.ios-playbook-managed"
assert_file "$HOME/.copilot/skills/ios-playbook/SKILL.md"
assert_file "$HOME/.copilot/agents/ios-playbook.agent.md"
[[ ! -L "$HOME/.claude/skills/ios-playbook" ]] || fail "copy mode should not create a symlink"
"$ROOT/install.sh" personal --claude --copilot >/dev/null
assert_link "$HOME/.claude/skills/ios-playbook"
"$ROOT/install.sh" uninstall-personal >/dev/null
assert_absent "$HOME/.claude/skills/ios-playbook"
assert_absent "$HOME/.copilot/skills/ios-playbook"
assert_absent "$HOME/.copilot/agents/ios-playbook.agent.md"

printf 'All installer tests passed.\n'
