#!/usr/bin/env bash
# Runs the skill's helper scripts against a fixture project and a throwaway git repo.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/skills/ios-playbook/scripts"
FIXTURE="$ROOT/tests/fixtures/sample-app"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect() {  # expect <text> <fixed string> <what>
  grep -qF -- "$2" <<<"$1" || fail "$3: expected to find: $2"
}

refute() {  # refute <text> <fixed string> <what>
  if grep -qF -- "$2" <<<"$1"; then fail "$3: did not expect: $2"; fi
}

# ------------------------------------------------------------ project-facts.sh
facts="$(bash "$SCRIPTS/project-facts.sh" "$FIXTURE")"

expect "$facts" '- FieldLog.xcodeproj' "projects"
expect "$facts" '- Packages/Core/Package.swift' "packages"
expect "$facts" '| `IPHONEOS_DEPLOYMENT_TARGET` | 18.0 (2); 17.0 (1) |' "deployment targets"
expect "$facts" '| `SWIFT_VERSION` | 6.0 (2); 5.0 (1) |' "swift versions"
expect "$facts" '| `SWIFT_DEFAULT_ACTOR_ISOLATION` | MainActor (2) |' "default isolation"
expect "$facts" '| `SWIFT_STRICT_CONCURRENCY` | complete (1) |' "strict concurrency"
expect "$facts" '| `SWIFT_TREAT_WARNINGS_AS_ERRORS` | YES (1) |' "xcconfig value with trailing comment"
expect "$facts" '`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` (2)' "upcoming features"
expect "$facts" 'swiftLanguageModes: [.v6]' "package language mode"
expect "$facts" '- FieldLog' "shared scheme"
expect "$facts" '- FieldLog.xctestplan' "test plan"
expect "$facts" 'SwiftData models (`@Model`): 2' "model count"
expect "$facts" '`FieldLog/Persistence/InspectionStore.swift:4` @ModelActor' "model actor"
expect "$facts" 'no `VersionedSchema`' "unversioned schema note"
expect "$facts" '| `@unchecked Sendable` | 1 | 1 |' "escape hatch count"
expect "$facts" '`FieldLog/Sync/SyncEngine.swift:2` @preconcurrency import Combine' "escape hatch list"
expect "$facts" '| `Testing` | 1 |' "Swift Testing import"
expect "$facts" '| `XCTest` | 1 |' "XCTest import"
expect "$facts" '- FieldLogTests' "test folder"
expect "$facts" '`.swiftlint.yml`: SwiftLint' "tooling"
refute "$facts" 'ShouldBeIgnored' "DerivedData must be skipped"
refute "$facts" 'project.xcworkspace' "the workspace inside the project is not a workspace"

# An empty folder must not crash the script.
mkdir -p "$TEST_ROOT/empty"
empty="$(bash "$SCRIPTS/project-facts.sh" "$TEST_ROOT/empty")"
expect "$empty" '0 Swift files' "empty folder"

if bash "$SCRIPTS/project-facts.sh" "$TEST_ROOT/does-not-exist" >/dev/null 2>&1; then
  fail "a missing path should be an error"
fi

# --------------------------------------------------------------- diff-audit.sh
repo="$TEST_ROOT/repo"
mkdir -p "$repo/App" "$repo/AppTests" "$repo/App.xcodeproj"
git -C "$repo" init --quiet
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config commit.gpgsign false

cat > "$repo/App/Trip.swift" <<'EOF'
import SwiftData

@Model final class Trip {
    var number: String
    init(number: String) { self.number = number }
}
EOF
cat > "$repo/App/Sync.swift" <<'EOF'
import Foundation

final class Sync {
    func run() async {}
}
EOF
cat > "$repo/AppTests/SyncTests.swift" <<'EOF'
import Testing

@Suite struct SyncTests {
    @Test func runsOnce() async {
        #expect(true)
    }

    @Test func retriesAfterTimeout() async {
        #expect(true)
    }
}
EOF
printf '// project\n' > "$repo/App.xcodeproj/project.pbxproj"
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "baseline"

clean="$(cd "$repo" && bash "$SCRIPTS/diff-audit.sh")"
expect "$clean" 'No changes to audit.' "clean tree"

cat > "$repo/App/Sync.swift" <<'EOF'
import Foundation

final class Sync: @unchecked Sendable {
    nonisolated(unsafe) static var shared = Sync()
    private let queue = DispatchQueue(label: "sync")

    func run() async {
        let url = URL(string: "https://example.com")!
        let data = try! Data(contentsOf: url)
        print(data.count)
        Task {
            try await Task.sleep(for: .seconds(1))
        }
        // TODO: handle errors
        // swiftlint:disable:next force_cast
        let apiKey = "abc123"
        let nonEmpty = data.count != 0
        if nonEmpty { fatalError("unexpected") }
        _ = apiKey
    }
}
EOF
cat > "$repo/App/Trip.swift" <<'EOF'
import SwiftData

@Model final class Trip {
    @Attribute(.unique) var number: String
    init(number: String) { self.number = number }
}
EOF
cat > "$repo/AppTests/SyncTests.swift" <<'EOF'
import Testing

@Suite struct SyncTests {
    @Test(.disabled("flaky")) func runsOnce() async {
        #expect(true)
    }
}
EOF
printf '// project changed\n' > "$repo/App.xcodeproj/project.pbxproj"
cat > "$repo/App/New.swift" <<'EOF'
import Foundation

struct New {
    let value = Optional(1)!
}
EOF

audit="$(cd "$repo" && bash "$SCRIPTS/diff-audit.sh")"

expect "$audit" '## Blockers' "blockers section"
expect "$audit" '### Concurrency silencers (2)' "silencers"
expect "$audit" '`App/Sync.swift:3` final class Sync: @unchecked Sendable {' "silencer line number"
expect "$audit" '### Forced try or cast (1)' "forced try"
expect "$audit" '### Lint suppressions (1)' "lint suppression in a comment"
expect "$audit" '### Tests disabled or skipped (1)' "disabled test"
expect "$audit" '### Test functions removed (1)' "removed test"
expect "$audit" '`AppTests/SyncTests.swift` func retriesAfterTimeout' "removed test name"
refute "$audit" '`AppTests/SyncTests.swift` func runsOnce' "an edited test is not a removed test"
expect "$audit" '### Possible force unwraps' "force unwraps"
expect "$audit" '`App/New.swift:4`' "untracked file is audited"
expect "$audit" '### Legacy concurrency (1)' "legacy concurrency"
expect "$audit" '### Unstructured tasks (1)' "unstructured task"
expect "$audit" '### Debug output (1)' "print"
expect "$audit" '### TODO, FIXME, HACK (1)' "todo"
expect "$audit" '### fatalError and preconditionFailure (1)' "fatalError"
expect "$audit" '### Sleeps (1)' "sleep"
expect "$audit" '### String literal assigned to something named like a secret (1)' "secret"
expect "$audit" '### Files with @Model types changed (1)' "model file"
expect "$audit" '`App/Trip.swift`' "model file name"
expect "$audit" '### Sensitive files changed (1)' "sensitive file"
expect "$audit" '`App.xcodeproj/project.pbxproj`' "project file"
refute "$audit" 'data.count != 0' "inequality is not a force unwrap"

# Strict mode turns blockers into a failing exit code.
if (cd "$repo" && PLAYBOOK_AUDIT_STRICT=1 bash "$SCRIPTS/diff-audit.sh" >/dev/null); then
  fail "strict mode should exit 1 when blockers exist"
fi

# Against a base branch: commit the changes on a branch and compare with the default branch.
default_branch="$(git -C "$repo" branch --show-current)"
git -C "$repo" checkout --quiet -b feature
git -C "$repo" add -A
git -C "$repo" commit --quiet -m "changes"
based="$(cd "$repo" && bash "$SCRIPTS/diff-audit.sh" "$default_branch")"
expect "$based" '### Concurrency silencers (2)' "audit against a base branch"

outside="$TEST_ROOT/not-a-repo"
mkdir -p "$outside"
if (cd "$outside" && GIT_CEILING_DIRECTORIES="$TEST_ROOT" bash "$SCRIPTS/diff-audit.sh" >/dev/null 2>&1); then
  fail "outside a git repository should be an error"
fi

printf 'script tests passed\n'
