#!/usr/bin/env bats
#
# Binary-level contract for `--format json`: the wire schema autonomous agents
# depend on. Builds the debug binary once, then drives it in a temp project.

setup_file() {
  cd "${BATS_TEST_DIRNAME}/../.." || exit 1
  swift build >/dev/null 2>&1
  export RELIOS="${BATS_TEST_DIRNAME}/../../.build/debug/relios"
}

setup() {
  RELIOS="${BATS_TEST_DIRNAME}/../../.build/debug/relios"
  PROJ="$(mktemp -d)"
  cd "$PROJ" || exit 1
  cat > relios.toml <<'EOF'
[app]
name = "Demo"
display_name = "Demo"
bundle_id = "com.acme.demo"
min_macos = "14.0"
category = "public.app-category.developer-tools"
[project]
type = "swiftpm"
root = "."
binary_target = "Demo"
[version]
source_file = "AppVersion.swift"
version_pattern = 'static let current = "(.*)"'
build_pattern = 'static let build = "(.*)"'
[build]
command = "swift build -c release"
binary_path = ".build/release/Demo"
resource_bundle_path = ""
[assets]
icon_path = ""
[bundle]
output_path = "dist/Demo.app"
plist_mode = "generate"
mode = "assembly"
[install]
path = "/Applications/Demo.app"
auto_open = false
backup_dir = "dist/app-backups"
keep_backups = 3
quit_running_app = true
[signing]
mode = "adhoc"
EOF
  printf 'enum AppVersion {\n  static let current = "1.2.3"\n  static let build = "4"\n}\n' > AppVersion.swift
}

teardown() {
  rm -rf "$PROJ"
}

@test "doctor --format json: valid single object, schema_version 1, every check has an id" {
  run "$RELIOS" doctor --format json
  echo "$output" | jq -e '.schema_version == 1' >/dev/null
  echo "$output" | jq -e '.checks | length > 0' >/dev/null
  echo "$output" | jq -e 'all(.checks[]; .id|length > 0)' >/dev/null
  echo "$output" | jq -e 'all(.checks[]; .severity|test("^(ok|warn|fail)$"))' >/dev/null
}

@test "capabilities --format json: reports schema_version and commands" {
  run "$RELIOS" capabilities --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.data.schema_version == 1' >/dev/null
  echo "$output" | jq -e '.data.commands | length > 0' >/dev/null
}

@test "version --format json: stdout is a single JSON object" {
  run "$RELIOS" version --format json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.data.version == "1.2.3" and .data.build == "4"' >/dev/null
}

@test "failure emits one error object on stdout with a stable id and exit 1" {
  rm relios.toml
  run "$RELIOS" doctor --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.status == "fail"' >/dev/null
  echo "$output" | jq -e '.error.id == "SPEC_NOT_FOUND"' >/dev/null
  echo "$output" | jq -e '.exit_code == 1' >/dev/null
  echo "$output" | jq -e '.error.requires_human | type == "boolean"' >/dev/null
}

@test "inspect with no manifest emits MANIFEST_NOT_FOUND" {
  run "$RELIOS" inspect --format json
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.error.id == "MANIFEST_NOT_FOUND"' >/dev/null
}

@test "RELIOS_FORMAT=json env var is honored without the flag" {
  RELIOS_FORMAT=json run "$RELIOS" doctor
  echo "$output" | jq -e '.schema_version == 1' >/dev/null
}
