#!/usr/bin/env bash
# ios-playbook installer for Claude Code and GitHub Copilot
# (VS Code, Copilot CLI, Copilot for Xcode).
# Safe to run repeatedly. Run ./install.sh help for usage.

set -euo pipefail

VERSION="1.0.0"
SKILL_NAME="ios-playbook"
AGENT_FILE="ios-playbook.agent.md"
INSTRUCTIONS_FILE="ios-playbook.instructions.md"
MARKER=".ios-playbook-managed"
BLOCK_START="<!-- ios-playbook:start -->"
BLOCK_END="<!-- ios-playbook:end -->"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SKILL="$SCRIPT_DIR/skills/$SKILL_NAME"
SRC_AGENT="$SCRIPT_DIR/agents/$AGENT_FILE"
SRC_INSTRUCTIONS="$SCRIPT_DIR/instructions/$INSTRUCTIONS_FILE"
SRC_BLOCK="$SRC_SKILL/assets/agents-block.md"

COPY_MODE=0
WANT_CLAUDE=0
WANT_COPILOT=0
FORCE=0

info()  { printf '  %s\n' "$*"; }
ok()    { printf '  [ok] %s\n' "$*"; }
warn()  { printf '  [warn] %s\n' "$*" >&2; }
fail()  { printf '  [error] %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
ios-playbook installer $VERSION

Usage:
  ./install.sh personal [--claude] [--copilot] [--copy] [--force]
      Install for all projects on this Mac (symlinks by default).
        Claude Code:  ~/.claude/skills/$SKILL_NAME
        Copilot:      ~/.copilot/skills/$SKILL_NAME
                      ~/.copilot/agents/$AGENT_FILE
      With neither --claude nor --copilot, installs for each tool whose home
      folder exists (~/.claude, ~/.copilot), or for both if neither exists.
      --copy    copy files instead of symlinking
      --force   replace existing files this script did not create (a timestamped backup is kept)

  ./install.sh project <path-to-repo> [--claude] [--copilot] [--force]
      Install into one repository. Files are copied so they can be committed.
        Claude Code:  .claude/skills/$SKILL_NAME/
                      CLAUDE.md (managed block; AGENTS.md is used if it exists and CLAUDE.md does not)
        Copilot:      .github/skills/$SKILL_NAME/
                      .github/agents/$AGENT_FILE
                      .github/instructions/$INSTRUCTIONS_FILE
                      .github/copilot-instructions.md (managed block)
      With neither flag, installs for each tool the repo already uses, or for both.
      Required for Copilot for Xcode, which reads the agent from the repo.

  ./install.sh uninstall-personal
  ./install.sh uninstall-project <path-to-repo>
  ./install.sh verify [<path-to-repo>]
  ./install.sh help
EOF
}

check_sources() {
  [[ -f "$SRC_SKILL/SKILL.md" ]] || fail "Missing $SRC_SKILL/SKILL.md. Run this script from the package folder."
  [[ -f "$SRC_AGENT" ]] || fail "Missing $SRC_AGENT"
  [[ -f "$SRC_INSTRUCTIONS" ]] || fail "Missing $SRC_INSTRUCTIONS"
  [[ -f "$SRC_BLOCK" ]] || fail "Missing $SRC_BLOCK"
  local name
  name="$(awk -F': *' '/^name:/{print $2; exit}' "$SRC_SKILL/SKILL.md" | tr -d "\"'")"
  [[ "$name" == "$SKILL_NAME" ]] || fail "SKILL.md name '$name' does not match folder '$SKILL_NAME'"
}

# lint_skill: the checks that make a skill load everywhere.
lint_skill() {
  local skill_md="$SRC_SKILL/SKILL.md" desc lines missing=0 ref
  desc="$(awk '/^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$skill_md")"
  desc="${desc#\'}"; desc="${desc%\'}"
  [[ -n "$desc" ]] || fail "SKILL.md has no description"
  [[ ${#desc} -le 1024 ]] || fail "SKILL.md description is ${#desc} characters (limit 1024)"
  ok "Description is ${#desc} characters (limit 1024)"
  lines="$(wc -l < "$skill_md" | tr -d ' ')"
  [[ "$lines" -le 500 ]] || fail "SKILL.md is $lines lines (limit 500)"
  ok "SKILL.md is $lines lines (limit 500)"
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if [[ ! -f "$SRC_SKILL/$ref" ]]; then
      warn "SKILL.md links to a missing file: $ref"
      missing=1
    fi
  done < <(grep -oE '\]\((references|assets|scripts)/[^)#]+' "$skill_md" | sed 's/^](//' | sort -u)
  [[ "$missing" == 0 ]] || fail "SKILL.md has broken links"
  ok "All files linked from SKILL.md exist"
  for ref in "$SRC_SKILL"/scripts/*.sh; do
    [[ -x "$ref" ]] || fail "Not executable: $ref"
  done
  ok "Helper scripts are executable"
}

backup() {
  local target="$1" stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  mv "$target" "$target.backup-$stamp"
  warn "Existing $target moved to $target.backup-$stamp"
}

# is_managed <path>: true if this installer created it.
is_managed() {
  local p="$1"
  if [[ -L "$p" ]]; then
    [[ "$(basename "$(readlink "$p")")" == "$(basename "$p")" ]]
    return
  fi
  if [[ -d "$p" ]]; then
    [[ -e "$p/$MARKER" ]]
    return
  fi
  [[ -f "$p" ]] && grep -qE "ios-playbook|iOS Playbook" "$p"
}

# place <source> <destination> <link|copy>
place() {
  local src="$1" dest="$2" mode="$3"
  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" && "$mode" == "link" && "$(readlink "$dest")" == "$src" ]]; then
    ok "Already linked: $dest"
    return
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    if is_managed "$dest"; then
      rm -rf "$dest"
    elif [[ "$FORCE" == 1 ]]; then
      backup "$dest"
    else
      fail "$dest already exists and was not installed by this script. Re-run with --force to back it up and replace it."
    fi
  fi

  if [[ "$mode" == "link" ]]; then
    ln -s "$src" "$dest"
    ok "Linked $dest"
  else
    cp -R "$src" "$dest"
    if [[ -d "$dest" ]]; then
      printf '%s\n' "$VERSION" > "$dest/$MARKER"
    fi
    ok "Copied $dest"
  fi
}

# remove_managed <path>: remove it only if this installer created it.
remove_managed() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    if is_managed "$p"; then
      rm -rf "$p"
      ok "Removed $p"
    else
      warn "Skipped $p (not managed by this script)"
    fi
  fi
}

trim_trailing_blank() {
  awk '{ lines[NR] = $0 } END { n = NR; while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }' "$1"
}

strip_block() {
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ' "$1"
}

merge_block() {
  local file="$1" tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  strip_block "$file" > "$tmp"
  trim_trailing_blank "$tmp" > "$tmp.trim"
  if [[ -s "$tmp.trim" ]]; then
    { cat "$tmp.trim"; printf '\n'; cat "$SRC_BLOCK"; } > "$file"
  else
    cat "$SRC_BLOCK" > "$file"
  fi
  rm -f "$tmp" "$tmp.trim"
  ok "Updated managed block in $file"
}

remove_block() {
  local file="$1" tmp
  [[ -f "$file" ]] || return 0
  grep -qF "$BLOCK_START" "$file" || return 0
  tmp="$(mktemp)"
  strip_block "$file" > "$tmp"
  if [[ -z "$(tr -d '[:space:]' < "$tmp")" ]]; then
    rm -f "$file"
    ok "Removed $file (it only contained the managed block)"
  else
    trim_trailing_blank "$tmp" > "$file"
    ok "Removed managed block from $file"
  fi
  rm -f "$tmp"
}

# claude_instruction_file <repo>: CLAUDE.md, or AGENTS.md when only that exists.
claude_instruction_file() {
  local repo="$1"
  if [[ ! -f "$repo/CLAUDE.md" && -f "$repo/AGENTS.md" ]]; then
    printf '%s\n' "$repo/AGENTS.md"
  else
    printf '%s\n' "$repo/CLAUDE.md"
  fi
}

# resolve_targets personal | resolve_targets project <repo>
resolve_targets() {
  [[ "$WANT_CLAUDE" == 1 || "$WANT_COPILOT" == 1 ]] && return 0
  if [[ "$1" == "personal" ]]; then
    [[ -d "$HOME/.claude" ]] && WANT_CLAUDE=1
    [[ -d "$HOME/.copilot" ]] && WANT_COPILOT=1
  else
    local repo="$2"
    if [[ -d "$repo/.claude" || -f "$repo/CLAUDE.md" ]]; then WANT_CLAUDE=1; fi
    if [[ -f "$repo/.github/copilot-instructions.md" || -d "$repo/.github/skills" \
          || -d "$repo/.github/agents" || -d "$repo/.github/instructions" ]]; then WANT_COPILOT=1; fi
  fi
  if [[ "$WANT_CLAUDE" == 0 && "$WANT_COPILOT" == 0 ]]; then
    WANT_CLAUDE=1
    WANT_COPILOT=1
  fi
  return 0
}

describe_targets() {
  if [[ "$WANT_CLAUDE" == 1 && "$WANT_COPILOT" == 1 ]]; then echo "Claude Code and Copilot"
  elif [[ "$WANT_CLAUDE" == 1 ]]; then echo "Claude Code"
  else echo "Copilot"
  fi
}

install_personal() {
  check_sources
  resolve_targets personal
  local mode="link"
  [[ "$COPY_MODE" == 1 ]] && mode="copy"
  echo "Installing the personal skill for $(describe_targets) ($mode mode)"
  if [[ "$WANT_CLAUDE" == 1 ]]; then
    place "$SRC_SKILL" "$HOME/.claude/skills/$SKILL_NAME" "$mode"
  fi
  if [[ "$WANT_COPILOT" == 1 ]]; then
    place "$SRC_SKILL" "$HOME/.copilot/skills/$SKILL_NAME" "$mode"
    place "$SRC_AGENT" "$HOME/.copilot/agents/$AGENT_FILE" "$mode"
  fi
  echo
  if [[ "$WANT_CLAUDE" == 1 ]]; then
    info "Claude Code: type /$SKILL_NAME map in a repo to build its repo map, then /$SKILL_NAME <task>."
  fi
  if [[ "$WANT_COPILOT" == 1 ]]; then
    info "Copilot: restart VS Code (or run /skills reload in Copilot CLI), then pick the iOS Playbook agent or type /$SKILL_NAME."
    if [[ -n "${IOS_PLAYBOOK_BOOTSTRAP:-}" ]]; then
      info "Copilot for Xcode needs a project install:"
      info "  curl -fsSL $IOS_PLAYBOOK_BOOTSTRAP | bash -s -- project /path/to/repo"
    else
      info "Copilot for Xcode needs a project install: ./install.sh project /path/to/repo"
    fi
  fi
}

install_project() {
  local repo="${1:-}"
  [[ -n "$repo" ]] || fail "Provide a repository path: ./install.sh project /path/to/repo"
  [[ -d "$repo" ]] || fail "Not a directory: $repo"
  check_sources
  repo="$(cd "$repo" && pwd)"
  resolve_targets project "$repo"
  echo "Installing into $repo for $(describe_targets)"
  if [[ "$WANT_CLAUDE" == 1 ]]; then
    place "$SRC_SKILL" "$repo/.claude/skills/$SKILL_NAME" copy
    merge_block "$(claude_instruction_file "$repo")"
  fi
  if [[ "$WANT_COPILOT" == 1 ]]; then
    place "$SRC_SKILL" "$repo/.github/skills/$SKILL_NAME" copy
    place "$SRC_AGENT" "$repo/.github/agents/$AGENT_FILE" copy
    place "$SRC_INSTRUCTIONS" "$repo/.github/instructions/$INSTRUCTIONS_FILE" copy
    merge_block "$repo/.github/copilot-instructions.md"
  fi
  echo
  info "Next: run the skill in map mode once (/$SKILL_NAME map) to create .playbook/repo-map.md and .playbook/risk-map.md."
  info "Commit the installed files if you want teammates and cloud agents to get them."
  if [[ "$WANT_COPILOT" == 1 ]]; then
    info "In Xcode: reopen the project in Copilot for Xcode and pick 'iOS Playbook' in the agent menu."
  fi
}

uninstall_personal() {
  echo "Removing personal install"
  remove_managed "$HOME/.claude/skills/$SKILL_NAME"
  remove_managed "$HOME/.copilot/skills/$SKILL_NAME"
  remove_managed "$HOME/.copilot/agents/$AGENT_FILE"
}

uninstall_project() {
  local repo="${1:-}"
  [[ -n "$repo" && -d "$repo" ]] || fail "Provide a repository path: ./install.sh uninstall-project /path/to/repo"
  repo="$(cd "$repo" && pwd)"
  echo "Removing project install from $repo"
  remove_managed "$repo/.claude/skills/$SKILL_NAME"
  remove_managed "$repo/.github/skills/$SKILL_NAME"
  remove_managed "$repo/.github/agents/$AGENT_FILE"
  remove_managed "$repo/.github/instructions/$INSTRUCTIONS_FILE"
  remove_block "$repo/CLAUDE.md"
  remove_block "$repo/AGENTS.md"
  remove_block "$repo/.github/copilot-instructions.md"
  info "The .playbook folder (repo map, risk map, plans) is yours and was left in place."
}

verify() {
  local repo="${1:-}" refs p
  echo "ios-playbook $VERSION"
  check_sources
  ok "Package is valid (name matches folder, all files present)"
  lint_skill
  refs="$(find "$SRC_SKILL/references" -name '*.md' | wc -l | tr -d ' ')"
  ok "$refs reference files"
  for p in "$HOME/.claude/skills/$SKILL_NAME/SKILL.md" \
           "$HOME/.copilot/skills/$SKILL_NAME/SKILL.md" "$HOME/.copilot/agents/$AGENT_FILE"; do
    if [[ -e "$p" ]]; then ok "Found $p"; else info "Not installed: $p"; fi
  done
  if [[ -n "$repo" ]]; then
    for p in "$repo/.claude/skills/$SKILL_NAME/SKILL.md" "$repo/.github/skills/$SKILL_NAME/SKILL.md" \
             "$repo/.github/agents/$AGENT_FILE" "$repo/.github/instructions/$INSTRUCTIONS_FILE"; do
      if [[ -e "$p" ]]; then ok "Found $p"; else info "Not installed: $p"; fi
    done
    for p in "$repo/CLAUDE.md" "$repo/AGENTS.md" "$repo/.github/copilot-instructions.md"; do
      if [[ -f "$p" ]] && grep -qF "$BLOCK_START" "$p"; then ok "Managed block in $p"; fi
    done
    for p in "$repo/.playbook/repo-map.md" "$repo/.playbook/risk-map.md"; do
      if [[ -e "$p" ]]; then ok "Found $p"; else info "Not created yet: $p (run the skill in map mode)"; fi
    done
  fi
}

cmd="${1:-help}"
shift || true
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --copy) COPY_MODE=1 ;;
    --claude) WANT_CLAUDE=1 ;;
    --copilot) WANT_COPILOT=1 ;;
    --force) FORCE=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

case "$cmd" in
  personal) install_personal ;;
  project) install_project "${1:-}" ;;
  uninstall-personal) uninstall_personal ;;
  uninstall-project) uninstall_project "${1:-}" ;;
  verify) verify "${1:-}" ;;
  help|-h|--help) usage ;;
  *) usage; exit 1 ;;
esac
