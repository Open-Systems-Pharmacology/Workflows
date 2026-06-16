#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../manage_description.sh"
  TMPDIR="$(mktemp -d)"
  DESC="$TMPDIR/DESCRIPTION"
}

teardown() {
  rm -rf "$TMPDIR"
}

write_desc() {
  printf '%s\n' "$@" > "$DESC"
}

# --- dispatch / shared IO contract -------------------------------------------

@test "no subcommand: exits non-zero with usage ::error::" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"::error title=Unknown subcommand::"* ]] || [[ "$output" == *"::error title=Unknown subcommand::"* ]]
}

@test "unknown subcommand: exits non-zero with usage ::error::" {
  run "$SCRIPT" frobnicate "$DESC"

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"::error title=Unknown subcommand::"* ]] || [[ "$output" == *"::error title=Unknown subcommand::"* ]]
}

@test "missing file: exits non-zero with ::error::" {
  run "$SCRIPT" bump-version "$TMPDIR/nope"

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"::error title=Missing DESCRIPTION::"* ]] || [[ "$output" == *"::error title=Missing DESCRIPTION::"* ]]
}

@test "missing Version field: exits non-zero with ::error:: annotation on stderr" {
  write_desc \
    "Package: foo" \
    "License: MIT"

  run "$SCRIPT" bump-version "$DESC"

  [ "$status" -ne 0 ]
  # The annotation must actually surface (regression: set -o pipefail used to
  # abort before this guard ran, swallowing the message).
  [[ "$stderr" == *"::error title=Invalid DESCRIPTION::"* ]] || [[ "$output" == *"::error title=Invalid DESCRIPTION::"* ]]
}

@test "stdout contains only key=value lines, diagnostics go to stderr" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run bash -c "'$SCRIPT' bump-version '$DESC' 2>/dev/null"

  [ "$status" -eq 0 ]
  # Every line of stdout must match KEY=VALUE (key may include digits/underscore; value may be empty)
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Z0-9_]+=.*$ ]] || {
      echo "Non key=value stdout line: $line"
      return 1
    }
  done <<< "$output"
}

# --- detect-version subcommand -----------------------------------------------

@test "detect-version: dev version reports IS_DEV_VERSION=true, no mutation" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo@*release" \
    "License: MIT"

  run "$SCRIPT" detect-version "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"IS_DEV_VERSION=true"* ]]
  [[ "$output" == *"PKG_VERSION=1.2.3.9000"* ]]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
  # No mutation: version and Remotes untouched.
  grep -q '^Version: 1.2.3.9000$' "$DESC"
  grep -q 'org/repo@\*release' "$DESC"
}

@test "detect-version: release version reports IS_DEV_VERSION=false" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "License: MIT"

  run "$SCRIPT" detect-version "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"IS_DEV_VERSION=false"* ]]
  grep -q '^Version: 1.2.3$' "$DESC"
}

# --- bump-version subcommand -------------------------------------------------

@test "bump-version: dev version bumps trailing component" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run "$SCRIPT" bump-version "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OLD_VERSION=1.2.3.9000"* ]]
  [[ "$output" == *"PKG_VERSION=1.2.3.9001"* ]]
  [[ "$output" == *"IS_DEV_VERSION=true"* ]]
  grep -q '^Version: 1.2.3.9001$' "$DESC"
}

@test "bump-version: release version is a no-op" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "License: MIT"

  run "$SCRIPT" bump-version "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OLD_VERSION=1.2.3"* ]]
  [[ "$output" == *"PKG_VERSION=1.2.3"* ]]
  [[ "$output" == *"IS_DEV_VERSION=false"* ]]
  grep -q '^Version: 1.2.3$' "$DESC"
}

@test "bump-version: never touches Remotes (REMOTES_ACTION=none)" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo" \
    "License: MIT"

  run "$SCRIPT" bump-version "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
  grep -q '^    org/repo$' "$DESC"
}

@test "bump-version: missing Version field errors" {
  write_desc \
    "Package: foo" \
    "License: MIT"

  run "$SCRIPT" bump-version "$DESC"

  [ "$status" -ne 0 ]
}

# --- pin-remotes subcommand --------------------------------------------------

@test "pin-remotes: bare entries get @*release and REMOTES_ACTION=added" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo," \
    "    other/pkg" \
    "License: MIT"

  run "$SCRIPT" pin-remotes "$DESC"

  [ "$status" -eq 0 ]
  grep -q 'org/repo@\*release,' "$DESC"
  grep -q 'other/pkg@\*release' "$DESC"
  [[ "$output" == *"REMOTES_ACTION=added"* ]]
}

@test "pin-remotes: already pinned reports REMOTES_ACTION=unchanged, no duplicates" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    org/repo@*release" \
    "License: MIT"

  run "$SCRIPT" pin-remotes "$DESC"

  [ "$status" -eq 0 ]
  count=$(grep -o '@\*release' "$DESC" | wc -l | tr -d ' ')
  [ "$count" = "1" ]
  [[ "$output" == *"REMOTES_ACTION=unchanged"* ]]
}

@test "pin-remotes: entry with a foreign @ref is re-pinned to @*release" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    org/repo@develop," \
    "    other/pkg@v1.0.0" \
    "License: MIT"

  run "$SCRIPT" pin-remotes "$DESC"

  [ "$status" -eq 0 ]
  grep -q 'org/repo@\*release,' "$DESC"
  grep -q 'other/pkg@\*release' "$DESC"
  ! grep -q '@develop' "$DESC"
  ! grep -q '@v1.0.0' "$DESC"
  [[ "$output" == *"REMOTES_ACTION=added"* ]]
}

@test "pin-remotes: no Remotes field reports REMOTES_ACTION=none" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "License: MIT"

  run "$SCRIPT" pin-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
}

@test "pin-remotes: block ends at next top-level field" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    org/repo" \
    "License: MIT" \
    "Suggests: bar"

  run "$SCRIPT" pin-remotes "$DESC"

  [ "$status" -eq 0 ]
  grep -q '^License: MIT$' "$DESC"
  grep -q '^Suggests: bar$' "$DESC"
  ! grep -q 'License.*@\*release' "$DESC"
}

# --- unpin-remotes subcommand ------------------------------------------------

@test "unpin-remotes: pinned entries get @*release stripped, REMOTES_ACTION=stripped" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo@*release," \
    "    other/pkg@*release" \
    "License: MIT"

  run "$SCRIPT" unpin-remotes "$DESC"

  [ "$status" -eq 0 ]
  ! grep -q '@\*release' "$DESC"
  grep -q 'org/repo' "$DESC"
  grep -q 'other/pkg' "$DESC"
  [[ "$output" == *"REMOTES_ACTION=stripped"* ]]
}

@test "unpin-remotes: already bare reports REMOTES_ACTION=unchanged" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo" \
    "License: MIT"

  run "$SCRIPT" unpin-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=unchanged"* ]]
  ! grep -q '@\*release' "$DESC"
}

@test "unpin-remotes: no Remotes field reports REMOTES_ACTION=none" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run "$SCRIPT" unpin-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
}
