#!/usr/bin/env bash
# diff-audit.sh: list things worth a second look in the current Swift diff.
#
#   diff-audit.sh            working tree (staged, unstaged, untracked) against HEAD
#   diff-audit.sh <base>     everything since the merge base with <base>, plus the working tree
#
# Read-only. Prints Markdown with file and line for each hit. It is a list for
# a reviewer, not a verdict: explain each hit in the report or fix it.
# Works with the bash 3.2 and BSD tools that ship with macOS.
#
# PLAYBOOK_AUDIT_MAX      hits shown per rule (default 15)
# PLAYBOOK_AUDIT_STRICT   set to 1 to exit 1 when a blocker is found

set -u

MAX="${PLAYBOOK_AUDIT_MAX:-15}"
STRICT="${PLAYBOOK_AUDIT_STRICT:-0}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "diff-audit: not inside a git repository" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

EMPTY_TREE="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
if [ -n "${1:-}" ]; then
  BASE="$(git merge-base "$1" HEAD 2>/dev/null)"
  if [ -z "$BASE" ]; then
    echo "diff-audit: cannot find a merge base with '$1'" >&2
    exit 2
  fi
  BASE_LABEL="merge base with $1 ($(git rev-parse --short "$BASE"))"
elif git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  BASE="HEAD"
  BASE_LABEL="HEAD ($(git rev-parse --short HEAD))"
else
  BASE="$EMPTY_TREE"
  BASE_LABEL="empty tree (no commits yet)"
fi

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t iosplaybook)"
trap 'rm -rf "$TMP"' EXIT

count_lines() { wc -l < "$1" | tr -d ' '; }

# ------------------------------------------------------------- collect the diff
git -c core.quotePath=false diff --no-color --no-ext-diff -U0 "$BASE" -- . > "$TMP/diff.txt" 2>/dev/null
git -c core.quotePath=false diff --name-only "$BASE" -- . > "$TMP/files.txt" 2>/dev/null
git -c core.quotePath=false ls-files -o --exclude-standard > "$TMP/untracked.txt" 2>/dev/null
cat "$TMP/untracked.txt" >> "$TMP/files.txt"
sort -u "$TMP/files.txt" -o "$TMP/files.txt"

# lines.tsv: kind (A added, D removed) <tab> file <tab> line <tab> text
awk '
  /^diff --git / { inhdr = 1; next }
  inhdr && /^--- / { old = substr($0, 5); sub(/^a\//, "", old); next }
  inhdr && /^\+\+\+ / { new = substr($0, 5); sub(/^b\//, "", new); next }
  /^@@ / { inhdr = 0; s = $0; sub(/^@@ -[0-9,]+ \+/, "", s); line = s + 0; next }
  inhdr { next }
  /^\+/ { printf "A\t%s\t%d\t%s\n", new, line, substr($0, 2); line++; next }
  /^-/  { printf "D\t%s\t0\t%s\n", old, substr($0, 2); next }
' "$TMP/diff.txt" > "$TMP/lines.tsv"

# Untracked Swift files count as fully added.
grep -E '\.swift$' "$TMP/untracked.txt" 2>/dev/null | while IFS= read -r f; do
  [ -f "$f" ] || continue
  awk -v f="$f" '{ printf "A\t%s\t%d\t%s\n", f, NR, $0 }' "$f"
done >> "$TMP/lines.tsv"

# -------------------------------------------------------------------- the rules
# rule <output file> <extended regex> [skip-comments]
# Matches added lines in Swift files and writes "`file:line` code".
rule() {
  RE="$2" SKIP="${3:-yes}" awk -F'\t' '
    $1 == "A" && $2 ~ /\.swift$/ {
      text = $4
      if (ENVIRON["SKIP"] == "yes" && text ~ /^[[:space:]]*\/\//) next
      if (text ~ ENVIRON["RE"]) {
        sub(/^[[:space:]]+/, "", text)
        printf "`%s:%d` %s\n", $2, $3, substr(text, 1, 140)
      }
    }
  ' "$TMP/lines.tsv" > "$1"
}

rule "$TMP/b-silencers.txt"   '@unchecked[[:space:]]+Sendable|nonisolated[(]unsafe[)]|@preconcurrency'
rule "$TMP/b-forced.txt"      'try!|[[:space:]]as![[:space:]]'
rule "$TMP/b-lint.txt"        'swiftlint:disable|swift-format-ignore|swiftformat:disable' no
rule "$TMP/b-disabled.txt"    '[.]disabled[(]|XCTSkip'

rule "$TMP/r-legacy.txt"      'DispatchQueue|DispatchGroup|DispatchSemaphore|OperationQueue|Task[.]detached|NSLock|os_unfair_lock'
rule "$TMP/r-tasks.txt"       '(^|[^A-Za-z0-9_.])Task[[:space:]]*([(][^)]*[)])?[[:space:]]*[{]'
rule "$TMP/r-debug.txt"       '(^|[^A-Za-z0-9_.])(print|debugPrint|dump|NSLog)[(]'
rule "$TMP/r-todo.txt"        'TODO|FIXME|HACK' no
rule "$TMP/r-fatal.txt"       'fatalError[(]|preconditionFailure[(]'
rule "$TMP/r-sleep.txt"       'Task[.]sleep|Thread[.]sleep|(^|[^A-Za-z0-9_.])u?sleep[(]'
rule "$TMP/r-secrets.txt"     '([Pp]assword|[Ss]ecret|[Tt]oken|[Aa]pi_?[Kk]ey)[A-Za-z0-9_]*[[:space:]]*(:[[:space:]]*String[[:space:]]*)?=[[:space:]]*"[^"]'

# Possible force unwraps: an identifier, ")" or "]" followed by "!" that is not
# "!=". try! and as! are reported separately, so they are removed first.
awk -F'\t' '
  $1 == "A" && $2 ~ /\.swift$/ {
    text = $4
    if (text ~ /^[[:space:]]*\/\//) next
    probe = text
    gsub(/try!/, "try", probe)
    gsub(/as!/, "as", probe)
    if (probe ~ /[]A-Za-z0-9_)]!([^="]|$)/) {
      sub(/^[[:space:]]+/, "", text)
      printf "`%s:%d` %s\n", $2, $3, substr(text, 1, 140)
    }
  }
' "$TMP/lines.tsv" > "$TMP/r-unwrap.txt"

# Functions removed from test files whose name does not reappear in the same
# file. A test that was only edited keeps its name, so it is not listed.
awk -F'\t' '
  function fname(s,   m) {
    if (match(s, /func[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
      m = substr(s, RSTART, RLENGTH)
      sub(/func[[:space:]]+/, "", m)
      return m
    }
    return ""
  }
  $2 !~ /\.swift$/ { next }
  $2 !~ /Tests?\// && $2 !~ /Tests?\.swift$/ { next }
  { name = fname($4); if (name == "") next }
  $1 == "A" { added[$2 SUBSEP name] = 1; next }
  $1 == "D" { removed[++count] = $2 SUBSEP name }
  END {
    for (i = 1; i <= count; i++) {
      if (!(removed[i] in added)) {
        split(removed[i], parts, SUBSEP)
        printf "`%s` func %s\n", parts[1], parts[2]
      }
    }
  }
' "$TMP/lines.tsv" > "$TMP/b-removed-tests.txt"

# Changed Swift files that declare @Model types.
awk -F'\t' '$2 ~ /\.swift$/ { print $2 }' "$TMP/lines.tsv" | sort -u > "$TMP/changed-swift.txt"
: > "$TMP/f-models.txt"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -qE '@Model([^A-Za-z]|$)' "$f" 2>/dev/null; then
    printf '`%s`\n' "$f" >> "$TMP/f-models.txt"
  fi
done < "$TMP/changed-swift.txt"

# Files where a mistake fails late: at signing, review or release.
grep -E 'project[.]pbxproj$|[.]entitlements$|Info[.]plist$|PrivacyInfo[.]xcprivacy$|[.]xcconfig$|Package[.]swift$|Package[.]resolved$|[.]xcscheme$|[.]xctestplan$|(^|/)Podfile|[.]github/workflows/|(^|/)fastlane/|ExportOptions[.]plist$' \
  "$TMP/files.txt" 2>/dev/null | sed -E 's/^(.*)$/`\1`/' > "$TMP/f-sensitive.txt"

# ---------------------------------------------------------------------- output
section() {  # section <title> <file> <advice>
  local n
  n="$(count_lines "$2")"
  [ "$n" -gt 0 ] || return 0
  echo "### $1 ($n)"
  echo
  echo "$3"
  echo
  head -n "$MAX" "$2" | sed 's/^/- /'
  if [ "$n" -gt "$MAX" ]; then
    echo "- ... and $((n - MAX)) more"
  fi
  echo
}

total() {  # total <file>... : sum of line counts
  local sum=0 f
  for f in "$@"; do
    sum=$((sum + $(count_lines "$f")))
  done
  echo "$sum"
}

files_changed="$(count_lines "$TMP/files.txt")"
swift_changed="$(count_lines "$TMP/changed-swift.txt")"
added="$(awk -F'\t' '$1 == "A" && $2 ~ /\.swift$/' "$TMP/lines.tsv" | wc -l | tr -d ' ')"
removed="$(awk -F'\t' '$1 == "D" && $2 ~ /\.swift$/' "$TMP/lines.tsv" | wc -l | tr -d ' ')"

blockers="$(total "$TMP/b-silencers.txt" "$TMP/b-forced.txt" "$TMP/b-lint.txt" "$TMP/b-disabled.txt" "$TMP/b-removed-tests.txt")"
review="$(total "$TMP/r-unwrap.txt" "$TMP/r-legacy.txt" "$TMP/r-tasks.txt" "$TMP/r-debug.txt" "$TMP/r-todo.txt" "$TMP/r-fatal.txt" "$TMP/r-sleep.txt" "$TMP/r-secrets.txt")"
filenotes="$(total "$TMP/f-models.txt" "$TMP/f-sensitive.txt")"

echo "# Diff audit"
echo
echo "- Compared with: $BASE_LABEL"
echo "- Files changed: $files_changed ($swift_changed Swift)"
echo "- Swift lines: +$added -$removed"
echo "- Blockers: $blockers, worth a look: $review, file notes: $filenotes"
echo

if [ "$files_changed" -eq 0 ]; then
  echo "No changes to audit."
  exit 0
fi

if [ "$added" -gt 150 ]; then
  echo "Note: $added added Swift lines is larger than one slice. If this is a single slice, consider splitting it."
  echo
fi

if [ "$blockers" -gt 0 ]; then
  echo "## Blockers"
  echo
  echo "The hard rules say fix these, or get the user's agreement and explain each one in the report."
  echo
  section "Concurrency silencers" "$TMP/b-silencers.txt" "These hide a data race report instead of fixing it."
  section "Forced try or cast" "$TMP/b-forced.txt" "A failure here is a crash. Handle the error or prove the invariant in a comment."
  section "Lint suppressions" "$TMP/b-lint.txt" "A rule was switched off. Fix the code or justify it."
  section "Tests disabled or skipped" "$TMP/b-disabled.txt" "Never disable a test to get to green."
  section "Test functions removed" "$TMP/b-removed-tests.txt" "These functions were deleted from test files and do not reappear there. If a test was renamed or moved, say so."
fi

if [ "$review" -gt 0 ]; then
  echo "## Worth a look"
  echo
  section "Possible force unwraps" "$TMP/r-unwrap.txt" "Pattern match only, so expect false positives such as text inside string literals."
  section "Legacy concurrency" "$TMP/r-legacy.txt" "New code should use structured concurrency unless it bridges an old API."
  section "Unstructured tasks" "$TMP/r-tasks.txt" "Check error handling, cancellation and whether ordering matters."
  section "Debug output" "$TMP/r-debug.txt" "Use the project logger, or remove."
  section "TODO, FIXME, HACK" "$TMP/r-todo.txt" "Finish it, or move it to the Follow-ups list in the report."
  section "fatalError and preconditionFailure" "$TMP/r-fatal.txt" "Confirm this state is truly unreachable."
  section "Sleeps" "$TMP/r-sleep.txt" "In tests this makes them slow and flaky. Inject a clock or await the real condition."
  section "String literal assigned to something named like a secret" "$TMP/r-secrets.txt" "Secrets belong in the Keychain or configuration, not in source."
fi

if [ "$filenotes" -gt 0 ]; then
  echo "## File notes"
  echo
  section "Files with @Model types changed" "$TMP/f-models.txt" "If a stored property, relationship or attribute changed and the store has shipped, this needs a new schema version and a migration test."
  section "Sensitive files changed" "$TMP/f-sensitive.txt" "Project, signing, privacy, dependency and CI files. Confirm each change was intended and is named in the plan."
fi

if [ "$blockers" -eq 0 ] && [ "$review" -eq 0 ] && [ "$filenotes" -eq 0 ]; then
  echo "No flags. Still read the diff top to bottom: this script only knows patterns."
  echo
fi

if [ "$STRICT" = "1" ] && [ "$blockers" -gt 0 ]; then
  exit 1
fi
exit 0
