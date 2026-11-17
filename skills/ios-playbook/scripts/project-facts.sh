#!/usr/bin/env bash
# project-facts.sh: print facts about an Apple platform project as Markdown.
#
#   project-facts.sh [path]      path defaults to the current directory
#
# Read-only. It never builds, never resolves packages and never writes into
# the project. Needs bash, find, grep, sed, awk, sort and uniq, and works with
# the bash 3.2 and BSD tools that ship with macOS.
#
# PLAYBOOK_FACTS_MAX   lines shown per list (default 12)

set -u

ROOT="${1:-.}"
if [ ! -d "$ROOT" ]; then
  echo "project-facts: not a directory: $ROOT" >&2
  exit 2
fi
cd "$ROOT" || exit 2

MAX="${PLAYBOOK_FACTS_MAX:-12}"
TMP="$(mktemp -d 2>/dev/null || mktemp -d -t iosplaybook)"
trap 'rm -rf "$TMP"' EXIT

# find_files <find expression>: paths relative to the root, build and
# dependency folders skipped.
find_files() {
  find . \( -name .git -o -name .build -o -name DerivedData -o -name Pods \
            -o -name Carthage -o -name node_modules -o -name .swiftpm \
            -o -name xcuserdata -o -name SourcePackages \) -prune \
         -o "$@" -print 2>/dev/null | sed 's|^\./||' | sort
}

count_lines() { wc -l < "$1" | tr -d ' '; }

# show <file>: up to MAX lines as a Markdown list, then how many were left out.
show() {
  local n
  n="$(count_lines "$1")"
  if [ "$n" -eq 0 ]; then
    echo "- none found"
    return 0
  fi
  head -n "$MAX" "$1" | sed 's/^/- /'
  if [ "$n" -gt "$MAX" ]; then
    echo "- ... and $((n - MAX)) more"
  fi
}

# grep_list <list file> <extended regex>: file:line:text for every match.
grep_list() {
  [ -s "$1" ] || return 0
  tr '\n' '\0' < "$1" | xargs -0 grep -nE -- "$2" /dev/null 2>/dev/null
}

# grep_files <list file> <extended regex>: names of matching files.
grep_files() {
  [ -s "$1" ] || return 0
  tr '\n' '\0' < "$1" | xargs -0 grep -lE -- "$2" /dev/null 2>/dev/null
}

# as_refs: turn file:line:text into "`file:line` text", trimmed.
as_refs() {
  sed -E 's/^([^:]+):([0-9]+):[[:space:]]*/`\1:\2` /' | cut -c1-170
}

find_files -type f -name '*.swift' > "$TMP/swift.txt"
find_files -type f \( -name 'project.pbxproj' -o -name '*.xcconfig' \) > "$TMP/settings.txt"
find_files -type f -name 'Package.swift' > "$TMP/packages.txt"
find_files -type d -name '*.xcodeproj' > "$TMP/projects.txt"
find_files -type d -name '*.xcworkspace' | grep -v '\.xcodeproj/' > "$TMP/workspaces.txt"
find_files -type f -name '*.xcscheme' | grep 'xcshareddata' > "$TMP/schemes.txt"
find_files -type f -name '*.xctestplan' > "$TMP/testplans.txt"

echo "# Project facts"
echo
echo "Root: \`$(pwd)\`"
echo

# ---------------------------------------------------------------- containers
echo "## Workspaces, projects and packages"
echo
echo "Workspaces:"
show "$TMP/workspaces.txt"
echo
echo "Xcode projects:"
show "$TMP/projects.txt"
echo
echo "Swift packages (Package.swift):"
show "$TMP/packages.txt"
echo
for f in project.yml Project.swift Tuist.swift; do
  if [ -f "$f" ]; then
    echo "Note: \`$f\` is present, so the Xcode project is probably generated. Edit the manifest, not the project file."
    echo
  fi
done

# ------------------------------------------------------------ build settings
# setting <KEY>: each distinct value with the number of places it is set.
setting() {
  [ -s "$TMP/settings.txt" ] || return 0
  tr '\n' '\0' < "$TMP/settings.txt" \
    | xargs -0 grep -hE -- "^[[:space:]]*\"?$1\"?(\[[^]]*\])?[[:space:]]*=" /dev/null 2>/dev/null \
    | sed -E 's/[[:space:]]*\/\/.*$//; s/[[:space:]]*;[[:space:]]*$//' \
    | sed -E 's/^[^=]*=[[:space:]]*//; s/^"//; s/"$//' \
    | sort | uniq -c | sort -rn \
    | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "%s (%d)\n", $0, n }'
}

echo "## Build settings"
echo
if [ -s "$TMP/settings.txt" ]; then
  echo "From \`project.pbxproj\` and \`.xcconfig\` files. The number is how many build configurations set that value. More than one value usually means targets differ, so check the target you are changing."
  echo
  echo "| Setting | Values |"
  echo "|---|---|"
  found=0
  for key in IPHONEOS_DEPLOYMENT_TARGET MACOSX_DEPLOYMENT_TARGET XROS_DEPLOYMENT_TARGET \
             WATCHOS_DEPLOYMENT_TARGET TVOS_DEPLOYMENT_TARGET SWIFT_VERSION \
             SWIFT_STRICT_CONCURRENCY SWIFT_DEFAULT_ACTOR_ISOLATION \
             SWIFT_APPROACHABLE_CONCURRENCY SWIFT_TREAT_WARNINGS_AS_ERRORS \
             TARGETED_DEVICE_FAMILY; do
    vals="$(setting "$key" | paste -sd ';' - | sed 's/;/; /g')"
    if [ -n "$vals" ]; then
      printf '| `%s` | %s |\n' "$key" "$vals"
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "| (none of the tracked settings are set explicitly) | |"
  fi
  echo
  tr '\n' '\0' < "$TMP/settings.txt" \
    | xargs -0 grep -hoE -- 'SWIFT_UPCOMING_FEATURE_[A-Z0-9_]+"?[[:space:]]*=[[:space:]]*[A-Za-z]+' /dev/null 2>/dev/null \
    | sed -E 's/"//g; s/[[:space:]]*=[[:space:]]*/ = /' | sort | uniq -c \
    | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "`%s` (%d)\n", $0, n }' > "$TMP/upcoming.txt"
  echo "Upcoming feature flags:"
  show "$TMP/upcoming.txt"
  echo
  echo "Unset settings fall back to Xcode defaults. To see resolved values for one scheme: \`xcodebuild -scheme <Scheme> -showBuildSettings\`."
else
  echo "No \`project.pbxproj\` or \`.xcconfig\` found."
fi
echo

# -------------------------------------------------------------- Package.swift
if [ -s "$TMP/packages.txt" ]; then
  echo "## Package manifests"
  echo
  head -n 8 "$TMP/packages.txt" | while IFS= read -r pkg; do
    echo "\`$pkg\`:"
    grep -nE -- 'swift-tools-version|platforms[[:space:]]*:|\.(iOS|macOS|visionOS|watchOS|tvOS|macCatalyst)\(|swiftLanguageModes|swiftLanguageVersions|swiftLanguageMode\(|defaultIsolation|enableUpcomingFeature|enableExperimentalFeature|strictConcurrency|unsafeFlags' "$pkg" 2>/dev/null \
      | sed -E 's/^([0-9]+):[[:space:]]*/- line \1: `/; s/$/`/' | cut -c1-170 | head -n "$MAX"
    echo
  done
  pkg_total="$(count_lines "$TMP/packages.txt")"
  if [ "$pkg_total" -gt 8 ]; then
    echo "... and $((pkg_total - 8)) more manifests not shown."
    echo
  fi
  echo "The tools version on line 1 is not the language mode. Look for \`swiftLanguageModes\` or a per-target \`.swiftLanguageMode(...)\`."
  echo
fi

# ------------------------------------------------------ schemes and test plans
echo "## Schemes and test plans"
echo
echo "Shared schemes:"
sed -E 's|.*/||; s|\.xcscheme$||' "$TMP/schemes.txt" | sort -u > "$TMP/scheme-names.txt"
show "$TMP/scheme-names.txt"
echo
echo "Test plans:"
show "$TMP/testplans.txt"
echo
echo "Schemes that are not shared, and package schemes, only show up in \`xcodebuild -list\`."
echo

# -------------------------------------------------------------------- sources
swift_total="$(count_lines "$TMP/swift.txt")"
echo "## Swift sources"
echo
echo "$swift_total Swift files (build and dependency folders excluded)."
echo
if [ "$swift_total" -gt 0 ]; then
  echo "| Imports | Files |"
  echo "|---|---|"
  for fw in SwiftUI UIKit AppKit SwiftData CoreData CloudKit Combine Observation Testing XCTest; do
    n="$(grep_files "$TMP/swift.txt" "^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+$fw([[:space:]]|\$)" | wc -l | tr -d ' ')"
    if [ "$n" -gt 0 ]; then
      printf '| `%s` | %s |\n' "$fw" "$n"
    fi
  done
  echo
  echo "Both \`Testing\` and \`XCTest\` in the table means the test suite is mixed. Match the framework of the file you are adding to."
  echo
fi

# ---------------------------------------------------------------- persistence
echo "## Persistence"
echo
if [ "$swift_total" -gt 0 ]; then
  grep_list "$TMP/swift.txt" '@Model([^A-Za-z]|$)' | as_refs > "$TMP/models.txt"
  grep_list "$TMP/swift.txt" 'VersionedSchema' | as_refs > "$TMP/versioned.txt"
  grep_list "$TMP/swift.txt" 'SchemaMigrationPlan|MigrationStage\.' | as_refs > "$TMP/migration.txt"
  grep_list "$TMP/swift.txt" 'ModelContainer\(' | as_refs > "$TMP/containers.txt"
  grep_list "$TMP/swift.txt" '@ModelActor' | as_refs > "$TMP/modelactors.txt"
  grep_list "$TMP/swift.txt" 'cloudKitDatabase|NSPersistentCloudKitContainer' | as_refs > "$TMP/cloudkit.txt"
  grep_list "$TMP/swift.txt" 'NSPersistentContainer|NSManagedObjectContext' | as_refs > "$TMP/coredata.txt"

  echo "SwiftData models (\`@Model\`): $(count_lines "$TMP/models.txt")"
  show "$TMP/models.txt"
  echo
  echo "Versioned schemas:"
  show "$TMP/versioned.txt"
  echo
  echo "Migration plans and stages:"
  show "$TMP/migration.txt"
  echo
  echo "Containers created (\`ModelContainer(\`):"
  show "$TMP/containers.txt"
  echo
  echo "Model actors:"
  show "$TMP/modelactors.txt"
  echo
  echo "CloudKit:"
  show "$TMP/cloudkit.txt"
  echo
  if [ -s "$TMP/coredata.txt" ]; then
    echo "Core Data:"
    show "$TMP/coredata.txt"
    echo
  fi
  find_files -type d -name '*.xcdatamodeld' > "$TMP/datamodels.txt"
  if [ -s "$TMP/datamodels.txt" ]; then
    echo "Core Data models:"
    show "$TMP/datamodels.txt"
    echo
  fi
  if [ -s "$TMP/models.txt" ] && [ ! -s "$TMP/versioned.txt" ]; then
    echo "Note: there are \`@Model\` types and no \`VersionedSchema\`. If this app has shipped, the first schema change needs a version 1 that matches the shipped models exactly."
    echo
  fi
else
  echo "- no Swift files found"
  echo
fi

# ---------------------------------------------------------------- concurrency
if [ "$swift_total" -gt 0 ]; then
  echo "## Concurrency"
  echo
  echo "| Pattern | Occurrences | Files |"
  echo "|---|---|---|"
  conc_row() {  # conc_row <label> <regex>
    local occ files
    occ="$(grep_list "$TMP/swift.txt" "$2" | wc -l | tr -d ' ')"
    files="$(grep_files "$TMP/swift.txt" "$2" | wc -l | tr -d ' ')"
    printf '| %s | %s | %s |\n' "$1" "$occ" "$files"
  }
  conc_row '`@unchecked Sendable`' '@unchecked[[:space:]]+Sendable'
  conc_row '`nonisolated(unsafe)`' 'nonisolated\(unsafe\)'
  conc_row '`@preconcurrency`' '@preconcurrency'
  conc_row '`DispatchQueue`, `OperationQueue`' 'DispatchQueue|OperationQueue'
  conc_row 'Semaphores and locks' 'DispatchSemaphore|NSLock|NSRecursiveLock|os_unfair_lock|OSAllocatedUnfairLock'
  conc_row '`Task.detached`' 'Task\.detached'
  conc_row 'Unstructured `Task {`' '(^|[^A-Za-z0-9_.])Task[[:space:]]*(\([^)]*\))?[[:space:]]*\{'
  conc_row 'Actors declared' '(^|[[:space:]])actor[[:space:]]+[A-Z]'
  conc_row '`@MainActor`' '@MainActor'
  conc_row '`try!` and `as!`' 'try!|[[:space:]]as![[:space:]]'
  echo
  grep_list "$TMP/swift.txt" '@unchecked[[:space:]]+Sendable|nonisolated\(unsafe\)|@preconcurrency' | as_refs > "$TMP/hatches.txt"
  echo "Escape hatches (each one is a place the compiler was told to stop checking):"
  show "$TMP/hatches.txt"
  echo
fi

# ---------------------------------------------------------------------- tests
find . \( -name .git -o -name .build -o -name DerivedData -o -name Pods -o -name Carthage \
          -o -name node_modules -o -name .swiftpm -o -name SourcePackages \) -prune \
       -o -type d \( -name '*Tests' -o -name '*UITests' \) -print 2>/dev/null \
  | sed 's|^\./||' | sort > "$TMP/testdirs.txt"
echo "## Tests"
echo
echo "Test folders:"
show "$TMP/testdirs.txt"
echo

# -------------------------------------------------------------------- tooling
echo "## Tooling and instruction files"
echo
tool_row() {  # tool_row <path> <meaning>
  if [ -e "$1" ]; then
    printf -- '- `%s`: %s\n' "$1" "$2"
  fi
}
{
  tool_row ".swiftlint.yml" "SwiftLint"
  tool_row ".swiftformat" "SwiftFormat"
  tool_row ".swift-format" "swift-format"
  tool_row "Makefile" "check it for build and test targets"
  tool_row "fastlane/Fastfile" "fastlane lanes"
  tool_row "project.yml" "XcodeGen manifest"
  tool_row "Project.swift" "Tuist manifest"
  tool_row "Podfile" "CocoaPods"
  tool_row "Cartfile" "Carthage"
  tool_row "Mintfile" "Mint"
  tool_row ".github/workflows" "GitHub Actions, often the most reliable source of build commands"
  tool_row ".gitlab-ci.yml" "GitLab CI"
  tool_row "ci_scripts" "Xcode Cloud scripts"
  tool_row ".mcp.json" "project MCP servers"
  tool_row "CLAUDE.md" "agent instructions"
  tool_row "AGENTS.md" "agent instructions"
  tool_row ".github/copilot-instructions.md" "agent instructions"
  tool_row ".playbook/repo-map.md" "repo map, read it first"
  tool_row ".playbook/risk-map.md" "risk map, read it first"
} > "$TMP/tooling.txt"
if [ -s "$TMP/tooling.txt" ]; then
  cat "$TMP/tooling.txt"
else
  echo "- none of the usual files found"
fi
echo

# ------------------------------------------------------------------------ git
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "## Git"
  echo
  echo "- Branch: \`$(git branch --show-current 2>/dev/null)\`"
  echo "- Uncommitted changes: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ') files"
  tags="$(git tag --sort=-creatordate 2>/dev/null | head -n 5 | paste -sd ',' - | sed 's/,/, /g')"
  if [ -n "$tags" ]; then
    echo "- Latest tags: $tags (release tags are evidence that a store has shipped)"
  else
    echo "- No tags. That is not proof the app has not shipped, so ask."
  fi
  echo
fi

echo "## Next"
echo
echo "- \`xcodebuild -list\` for every scheme, then \`xcodebuild -scheme <Scheme> -showdestinations\`."
echo "- Build once and run the unit tests to take a baseline before the first edit."
