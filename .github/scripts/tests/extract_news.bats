#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../extract_news.sh"
  TMPDIR="$(mktemp -d)"
  NEWS="$TMPDIR/NEWS.md"
}

teardown() {
  rm -rf "$TMPDIR"
}

write_news() {
  printf '%s\n' "$@" > "$NEWS"
}

@test "extracts the section for '# pkg x.y.z' and stops at the next top-level heading" {
  write_news \
    "# mypkg (development version)" \
    "" \
    "* dev note" \
    "" \
    "# mypkg 1.2.3" \
    "" \
    "* First bullet" \
    "* Second bullet" \
    "" \
    "# mypkg 1.2.2" \
    "" \
    "* Old note"

  run "$SCRIPT" 1.2.3 "$NEWS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"First bullet"* ]]
  [[ "$output" == *"Second bullet"* ]]
  [[ "$output" != *"Old note"* ]]
  [[ "$output" != *"dev note"* ]]
}

@test "keeps nested subsections (## ...) within the version section" {
  write_news \
    "# mypkg 1.2.3" \
    "" \
    "* Top bullet" \
    "" \
    "## Bug fixes" \
    "" \
    "* A fix" \
    "" \
    "# mypkg 1.2.2" \
    "" \
    "* Old"

  run "$SCRIPT" 1.2.3 "$NEWS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Top bullet"* ]]
  [[ "$output" == *"## Bug fixes"* ]]
  [[ "$output" == *"A fix"* ]]
  [[ "$output" != *"Old"* ]]
}

@test "matches a bare '## x.y.z' heading" {
  write_news \
    "## 1.2.3" \
    "" \
    "* bullet a" \
    "" \
    "## 1.2.2" \
    "" \
    "* old"

  run "$SCRIPT" 1.2.3 "$NEWS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"bullet a"* ]]
  [[ "$output" != *"old"* ]]
}

@test "matches a dev version token (x.y.z.NNNN)" {
  write_news \
    "# mypkg 1.2.3.9000" \
    "" \
    "* dev bullet"

  run "$SCRIPT" 1.2.3.9000 "$NEWS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"dev bullet"* ]]
}

@test "version 1.2.3 does not match 1.2.30 (whole-token boundary)" {
  write_news \
    "# pkg 1.2.30" \
    "" \
    "* should not be picked"

  # Discard stderr so the diagnostic doesn't pollute $output (the section body
  # contract is stdout-only). `run bash -c` keeps this portable across bats
  # versions (no --separate-stderr flag, which needs bats >= 1.5).
  run bash -c "'$SCRIPT' 1.2.3 '$NEWS' 2>/dev/null"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no matching section: empty stdout, exit 0" {
  write_news \
    "# mypkg 1.2.3" \
    "" \
    "* bullet"

  run bash -c "'$SCRIPT' 9.9.9 '$NEWS' 2>/dev/null"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing NEWS file: empty stdout, exit 0" {
  run bash -c "'$SCRIPT' 1.2.3 '$TMPDIR/nope.md' 2>/dev/null"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing version argument: exits non-zero with ::error::" {
  run "$SCRIPT"

  [ "$status" -ne 0 ]
  # bats folds stderr into $output by default, so the annotation lands there.
  [[ "$output" == *"::error title=Missing version::"* ]]
}

@test "trims leading and trailing blank lines from the section" {
  write_news \
    "# mypkg 1.2.3" \
    "" \
    "" \
    "* only bullet" \
    "" \
    "" \
    "# mypkg 1.2.2" \
    "" \
    "* old"

  run "$SCRIPT" 1.2.3 "$NEWS"

  [ "$status" -eq 0 ]
  # First and last lines are non-blank content.
  first_line="$(printf '%s\n' "$output" | head -1)"
  last_line="$(printf '%s\n' "$output" | tail -1)"
  [ "$first_line" = "* only bullet" ]
  [ "$last_line" = "* only bullet" ]
}
