#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../rbuildignore_to_globs.sh"
  TMPDIR="$(mktemp -d)"
  RBI="$TMPDIR/.Rbuildignore"
}

teardown() {
  rm -rf "$TMPDIR"
}

write_rbi() {
  printf '%s\n' "$@" > "$RBI"
}

@test "missing file: exits 0 with no output" {
  run "$SCRIPT" "$TMPDIR/does-not-exist"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "anchored bare name: emits both name and name/**" {
  write_rbi '^docs$'
  run "$SCRIPT" "$RBI"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'docs'
  printf '%s\n' "$output" | grep -qx 'docs/\*\*'
}

@test "escaped dot in anchored pattern: handled as literal dot" {
  write_rbi '^README\.Rmd$'
  run "$SCRIPT" "$RBI"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'README.Rmd'
  printf '%s\n' "$output" | grep -qx 'README.Rmd/\*\*'
}

@test "extension pattern (anchored end only): emits **/*.ext" {
  write_rbi '\.Rproj$'
  run "$SCRIPT" "$RBI"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx '\*\*/\*\.Rproj'
}

@test "blank lines and comments are skipped" {
  write_rbi '^docs$' '' '# a comment' '   ' '^revdep$'
  out=$(bash "$SCRIPT" "$RBI" 2>/dev/null)
  printf '%s\n' "$out" | grep -qx 'docs'
  printf '%s\n' "$out" | grep -qx 'revdep'
  # 2 patterns x 2 globs each = 4 lines
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "4" ]
}

@test "nested path: ^tests/dev$ becomes tests/dev and tests/dev/**" {
  write_rbi '^tests/dev$'
  run "$SCRIPT" "$RBI"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx 'tests/dev'
  printf '%s\n' "$output" | grep -qx 'tests/dev/\*\*'
}

@test "unsupported pattern with regex metachars: warns on stderr and skips" {
  write_rbi '^foo|bar$' '^docs$'
  run "$SCRIPT" "$RBI"
  [ "$status" -eq 0 ]
  # docs is still emitted
  printf '%s\n' "$output" | grep -qx 'docs'
  # The unsupported one is not in stdout
  ! printf '%s\n' "$output" | grep -q 'foo|bar'
  # And combined output (run merges stderr into stdout when run with default flags?
  # Actually `run` captures stdout only by default. Re-run capturing stderr.
  err=$(bash "$SCRIPT" "$RBI" 2>&1 >/dev/null)
  [[ "$err" == *"Skipping unsupported pattern"* ]]
}

@test "unanchored bare name: emits **/name and **/name/**" {
  write_rbi 'TODO'
  run "$SCRIPT" "$RBI"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qx '\*\*/TODO'
  printf '%s\n' "$output" | grep -qx '\*\*/TODO/\*\*'
}

@test "typical R package .Rbuildignore: produces expected glob set" {
  write_rbi \
    '^.*\.Rproj$' \
    '^\.Rproj\.user$' \
    '^\.github$' \
    '^docs$' \
    '^_pkgdown\.yml$' \
    '^README\.Rmd$' \
    '^cran-comments\.md$' \
    '^revdep$'

  # Capture stdout only; stderr carries the warning for the unsupported pattern.
  out=$(bash "$SCRIPT" "$RBI" 2>/dev/null)
  # ^.*\.Rproj$ contains '*' which is a regex metachar -> should be skipped with warning
  # The remaining 7 patterns each emit 2 globs = 14 lines
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "14" ]
  printf '%s\n' "$out" | grep -qx '.github'
  printf '%s\n' "$out" | grep -qx '.github/\*\*'
  printf '%s\n' "$out" | grep -qx 'docs/\*\*'
  printf '%s\n' "$out" | grep -qx '_pkgdown.yml'
  printf '%s\n' "$out" | grep -qx 'cran-comments.md'
}
