#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/update-tap-formula.sh"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  # Source the script to expose transform_formula without running main.
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

@test "transform: replaces url and sha256 on canonical formula" {
  run bash -c "source '$SCRIPT' && cat '$FIXTURES/formula.v0.1.0-alpha.rb' | transform_formula v0.2.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa papa-channy/relios"
  [ "$status" -eq 0 ]
  [[ "$output" == *'url "https://github.com/papa-channy/relios/archive/refs/tags/v0.2.0.tar.gz"'* ]]
  [[ "$output" == *'sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'* ]]
  # Old values must be gone.
  [[ "$output" != *'v0.1.0-alpha.tar.gz'* ]]
  [[ "$output" != *'0f384f1697ca4264af0c8b58743ab9f2d473750f9c37239a3ae193148514f00c'* ]]
}

@test "transform: idempotent on same inputs" {
  local sha="0f384f1697ca4264af0c8b58743ab9f2d473750f9c37239a3ae193148514f00c"
  local cur
  cur=$(cat "$FIXTURES/formula.v0.1.0-alpha.rb")
  local out
  out=$(printf '%s' "$cur" | transform_formula v0.1.0-alpha "$sha" papa-channy/relios)
  [ "$cur" = "$out" ]
}

@test "transform: accepts uppercase sha256 in existing formula" {
  local cur='  sha256 "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890"'
  local out
  out=$(printf '%s' "$cur" | transform_formula v1.0.0 0000000000000000000000000000000000000000000000000000000000000000 papa-channy/relios)
  [[ "$out" == *'sha256 "0000000000000000000000000000000000000000000000000000000000000000"'* ]]
}

@test "transform: leaves sha256 untouched when url line absent" {
  # No url with archive/refs/tags -> sed no-op. sha256 still replaced (separate awk pass).
  run bash -c "source '$SCRIPT' && cat '$FIXTURES/formula.no-url.rb' | transform_formula v0.2.0 1111111111111111111111111111111111111111111111111111111111111111 papa-channy/relios"
  [ "$status" -eq 0 ]
  [[ "$output" == *'sha256 "1111111111111111111111111111111111111111111111111111111111111111"'* ]]
  [[ "$output" != *'archive/refs/tags/v0.2.0'* ]]
}

@test "transform: replaces only the first sha256 match" {
  local input=$'  url "https://github.com/papa-channy/relios/archive/refs/tags/v0.1.0.tar.gz"\n  sha256 "0000000000000000000000000000000000000000000000000000000000000000"\n  # second sha256 in a comment or bottle:\n  sha256 "1111111111111111111111111111111111111111111111111111111111111111"\n'
  local out
  out=$(printf '%s' "$input" | transform_formula v0.2.0 2222222222222222222222222222222222222222222222222222222222222222 papa-channy/relios)
  # First sha256 replaced with new value.
  [[ "$out" == *'sha256 "2222222222222222222222222222222222222222222222222222222222222222"'* ]]
  # Second sha256 preserved.
  [[ "$out" == *'sha256 "1111111111111111111111111111111111111111111111111111111111111111"'* ]]
  # Original first sha256 gone.
  [[ "$out" != *'sha256 "0000000000000000000000000000000000000000000000000000000000000000"'* ]]
}

@test "transform: preserves non-target lines verbatim" {
  run bash -c "source '$SCRIPT' && cat '$FIXTURES/formula.v0.1.0-alpha.rb' | transform_formula v0.2.0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa papa-channy/relios"
  [ "$status" -eq 0 ]
  [[ "$output" == *'desc "Local release pipeline CLI for SwiftPM macOS apps"'* ]]
  [[ "$output" == *'homepage "https://github.com/papa-channy/relios"'* ]]
  [[ "$output" == *'license "MIT"'* ]]
  [[ "$output" == *'depends_on xcode: ["15.0", :build]'* ]]
}
