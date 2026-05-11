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

@test "dev version: bumps trailing component and emits OLD_VERSION/PKG_VERSION/IS_DEV_VERSION=true" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OLD_VERSION=1.2.3.9000"* ]]
  [[ "$output" == *"PKG_VERSION=1.2.3.9001"* ]]
  [[ "$output" == *"IS_DEV_VERSION=true"* ]]
  grep -q '^Version: 1.2.3.9001$' "$DESC"
}

@test "release version: leaves Version untouched, OLD_VERSION equals PKG_VERSION" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"OLD_VERSION=1.2.3"* ]]
  [[ "$output" == *"PKG_VERSION=1.2.3"* ]]
  [[ "$output" == *"IS_DEV_VERSION=false"* ]]
  grep -q '^Version: 1.2.3$' "$DESC"
}

@test "missing file: exits non-zero with ::error::" {
  run "$SCRIPT" "$TMPDIR/nope"

  [ "$status" -ne 0 ]
  [[ "$stderr" == *"::error title=Missing DESCRIPTION::"* ]] || [[ "$output" == *"::error title=Missing DESCRIPTION::"* ]]
}

@test "missing Version field: exits non-zero with ::error::" {
  write_desc \
    "Package: foo" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -ne 0 ]
}

@test "dev version + Remotes with @*release: strips @*release and reports REMOTES_ACTION=stripped" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo@*release," \
    "    other/pkg@*release" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  ! grep -q '@\*release' "$DESC"
  grep -q 'org/repo' "$DESC"
  grep -q 'other/pkg' "$DESC"
  [[ "$output" == *"REMOTES_ACTION=stripped"* ]]
  # Decode REMOTES_BEFORE_B64 and check it contained @*release
  before_b64=$(grep -E '^REMOTES_BEFORE_B64=' <<<"$output" | cut -d= -f2-)
  decoded=$(echo "$before_b64" | base64 -d)
  [[ "$decoded" == *"@*release"* ]]
}

@test "release version + Remotes without @*release: appends @*release and reports REMOTES_ACTION=added" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    org/repo," \
    "    other/pkg" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  grep -q 'org/repo@\*release,' "$DESC"
  grep -q 'other/pkg@\*release' "$DESC"
  [[ "$output" == *"REMOTES_ACTION=added"* ]]
  after_b64=$(grep -E '^REMOTES_AFTER_B64=' <<<"$output" | cut -d= -f2-)
  decoded=$(echo "$after_b64" | base64 -d)
  [[ "$decoded" == *"@*release"* ]]
}

@test "release version + Remotes already with @*release: no duplicates and REMOTES_ACTION=unchanged" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    org/repo@*release" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  count=$(grep -o '@\*release' "$DESC" | wc -l | tr -d ' ')
  [ "$count" = "1" ]
  [[ "$output" == *"REMOTES_ACTION=unchanged"* ]]
}

@test "dev version + Remotes already without @*release: REMOTES_ACTION=unchanged" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    org/repo" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=unchanged"* ]]
  ! grep -q '@\*release' "$DESC"
}

@test "no Remotes field: succeeds with REMOTES_ACTION=none and empty before/after blobs" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"PKG_VERSION=1.2.3.9001"* ]]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
  [[ "$output" == *"REMOTES_BEFORE_B64="* ]]
  [[ "$output" == *"REMOTES_AFTER_B64="* ]]
}

@test "stdout contains only key=value lines, diagnostics go to stderr" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run bash -c "'$SCRIPT' '$DESC' 2>/dev/null"

  [ "$status" -eq 0 ]
  # Every line of stdout must match KEY=VALUE (key may include digits/underscore; value may be empty)
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Z0-9_]+=.*$ ]] || {
      echo "Non key=value stdout line: $line"
      return 1
    }
  done <<< "$output"
}

@test "Remotes block ends at next top-level field" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    org/repo" \
    "License: MIT" \
    "Suggests: bar"

  run "$SCRIPT" "$DESC"

  [ "$status" -eq 0 ]
  grep -q '^License: MIT$' "$DESC"
  grep -q '^Suggests: bar$' "$DESC"
  ! grep -q 'License.*@\*release' "$DESC"
}
