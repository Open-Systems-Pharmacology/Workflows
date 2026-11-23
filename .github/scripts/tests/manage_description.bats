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

# Fails unless grep finds no match (status 1). A negated command such as
# `! grep ...` does not fail a Bats test unless it is the last command, and it
# would also hide a grep error (status 2).
refute_grep() {
  local status=0
  grep "$@" || status=$?
  if [ "$status" -ne 1 ]; then
    echo "expected no match (status 1), got status $status: grep $*"
    return 1
  fi
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

# --- release-remotes subcommand ----------------------------------------------

@test "release-remotes: tracking remotes move to Config/osp/dev-remotes, R-universe added" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/OSPSuite.RUtils," \
    "    tlf=Open-Systems-Pharmacology/TLF-Library," \
    "    github::esqLABS/osp.snapshots" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=released"* ]]
  refute_grep -q '^Remotes:' "$DESC"
  grep -q '^Config/osp/dev-remotes:$' "$DESC"
  grep -q '^    Open-Systems-Pharmacology/OSPSuite.RUtils,$' "$DESC"
  grep -q '^    tlf=Open-Systems-Pharmacology/TLF-Library,$' "$DESC"
  grep -q '^    github::esqLABS/osp.snapshots$' "$DESC"
  grep -q '^Additional_repositories:$' "$DESC"
  grep -q '^    https://open-systems-pharmacology.r-universe.dev,$' "$DESC"
  grep -q '^    https://esqlabs.r-universe.dev$' "$DESC"
  grep -q '^License: MIT$' "$DESC"
}

@test "release-remotes: legacy @*release entries count as tracking" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/repo@*release" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  refute_grep -q '@\*release' "$DESC"
  refute_grep -q '^Remotes:' "$DESC"
  grep -q '^    Open-Systems-Pharmacology/repo$' "$DESC"
  grep -q 'https://open-systems-pharmacology.r-universe.dev' "$DESC"
}

@test "release-remotes: pinned and non-GitHub remotes move too, Remotes is dropped" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/pinned@v2.0.0," \
    "    Open-Systems-Pharmacology/tracked," \
    "    url::https://example.com/pkg.tar.gz" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=released"* ]]
  refute_grep -q '^Remotes:' "$DESC"
  [ "$(awk '/^Config\/osp\/dev-remotes:/{r=1;next} r&&/^[^ ]/{exit} r' "$DESC")" = "$(printf '    Open-Systems-Pharmacology/pinned@v2.0.0,\n    Open-Systems-Pharmacology/tracked,\n    url::https://example.com/pkg.tar.gz')" ]
  [ "$(grep -c 'r-universe.dev' "$DESC")" = "2" ]
  [[ "$output" == *"::warning title=Remote ref dropped::"* ]]
  [[ "$output" == *"::warning title=No R-universe for remote::"* ]]
}

@test "release-remotes: keeps an existing Additional_repositories line, no duplicate URL" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/OSPSuite.Plots" \
    "Additional_repositories: https://open-systems-pharmacology.r-universe.dev/" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  grep -q '^Additional_repositories: https://open-systems-pharmacology.r-universe.dev/$' "$DESC"
  [ "$(grep -c 'r-universe.dev' "$DESC")" = "1" ]
}

@test "release-remotes: idempotent, second run reports unchanged" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/repo" \
    "License: MIT"

  "$SCRIPT" release-remotes "$DESC" >/dev/null 2>&1
  cp "$DESC" "$TMPDIR/first"
  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=unchanged"* ]]
  cmp -s "$DESC" "$TMPDIR/first"
}

@test "release-remotes: no Remotes field reports REMOTES_ACTION=none" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
  refute_grep -q 'Additional_repositories' "$DESC"
}

@test "release-remotes: a pinned OSP remote moves and its R-universe is added" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/rSharp@v2.0.0" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=released"* ]]
  refute_grep -q '^Remotes:' "$DESC"
  grep -q '^    Open-Systems-Pharmacology/rSharp@v2.0.0$' "$DESC"
  grep -q 'https://open-systems-pharmacology.r-universe.dev' "$DESC"
}

# --- dev-remotes subcommand --------------------------------------------------

@test "dev-remotes: stored remotes move back to Remotes" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Config/osp/dev-remotes:" \
    "    Open-Systems-Pharmacology/repo," \
    "    pkg=esqLABS/pkg" \
    "Additional_repositories:" \
    "    https://open-systems-pharmacology.r-universe.dev" \
    "License: MIT"

  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=restored"* ]]
  refute_grep -q 'Config/osp/dev-remotes' "$DESC"
  grep -q '^Remotes:$' "$DESC"
  grep -q '^    Open-Systems-Pharmacology/repo,$' "$DESC"
  grep -q '^    pkg=esqLABS/pkg$' "$DESC"
  # Additional_repositories is left alone: Remotes win over repos in pak.
  grep -q '^    https://open-systems-pharmacology.r-universe.dev$' "$DESC"
}

@test "dev-remotes: merges stored remotes after kept pins" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/pinned@v2.0.0" \
    "Config/osp/dev-remotes:" \
    "    Open-Systems-Pharmacology/tracked" \
    "License: MIT"

  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [ "$(awk '/^Remotes:/{r=1;next} r&&/^[^ ]/{exit} r' "$DESC")" = "$(printf '    Open-Systems-Pharmacology/pinned@v2.0.0,\n    Open-Systems-Pharmacology/tracked')" ]
  refute_grep -q 'Config/osp/dev-remotes' "$DESC"
}

@test "dev-remotes: legacy @*release refs are stripped" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/repo@*release," \
    "    esqLABS/pkg@*release" \
    "License: MIT"

  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=restored"* ]]
  refute_grep -q '@\*release' "$DESC"
  grep -q '^    Open-Systems-Pharmacology/repo,$' "$DESC"
  grep -q '^    esqLABS/pkg$' "$DESC"
}

@test "dev-remotes: already in dev mode keeps the file byte-identical" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes: Open-Systems-Pharmacology/repo, esqLABS/pkg" \
    "License: MIT"
  cp "$DESC" "$TMPDIR/orig"

  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=unchanged"* ]]
  cmp -s "$DESC" "$TMPDIR/orig"
}

@test "dev-remotes: no Remotes field reports REMOTES_ACTION=none" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "License: MIT"

  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=none"* ]]
}

@test "release then dev round-trips the Remotes block" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/pinned@v2.0.0," \
    "    Open-Systems-Pharmacology/tracked" \
    "Additional_repositories: https://open-systems-pharmacology.r-universe.dev" \
    "License: MIT"
  cp "$DESC" "$TMPDIR/orig"

  "$SCRIPT" release-remotes "$DESC" >/dev/null 2>&1
  "$SCRIPT" dev-remotes "$DESC" >/dev/null 2>&1

  cmp -s "$DESC" "$TMPDIR/orig"
}

@test "release-remotes: owners without an R-universe move with a warning, no URL added" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "    someone/elsewhere," \
    "    Open-Systems-Pharmacology/OSPSuite.RUtils" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  refute_grep -q '^Remotes:' "$DESC"
  grep -q '^    someone/elsewhere,$' "$DESC"
  refute_grep -q 'someone.r-universe.dev' "$DESC"
  grep -q 'open-systems-pharmacology.r-universe.dev' "$DESC"
  [[ "$output" == *"::warning title=No R-universe for remote::'someone/elsewhere'"* ]]
}

@test "release then dev removes only the repositories the release added" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    Open-Systems-Pharmacology/OSPSuite.RUtils," \
    "    esqLABS/osp.snapshots" \
    "Additional_repositories: https://open-systems-pharmacology.r-universe.dev" \
    "License: MIT"

  "$SCRIPT" release-remotes "$DESC" >/dev/null 2>&1
  grep -q '^Config/osp/release-repositories:$' "$DESC"
  grep -q '^    https://esqlabs.r-universe.dev$' "$DESC"
  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  refute_grep -q 'Config/osp/release-repositories' "$DESC"
  refute_grep -q 'esqlabs.r-universe.dev' "$DESC"
  grep -q 'https://open-systems-pharmacology.r-universe.dev' "$DESC"
}

@test "release then dev with no Additional_repositories is byte-identical" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    ospsuite=Open-Systems-Pharmacology/OSPSuite-R," \
    "    tlf=Open-Systems-Pharmacology/TLF-Library" \
    "License: MIT"
  cp "$DESC" "$TMPDIR/orig"

  "$SCRIPT" release-remotes "$DESC" >/dev/null 2>&1
  grep -q '^Additional_repositories:$' "$DESC"
  "$SCRIPT" dev-remotes "$DESC" >/dev/null 2>&1

  cmp -s "$DESC" "$TMPDIR/orig"
}

@test "release-remotes: CRLF DESCRIPTION (Windows checkout) is parsed" {
  printf 'Package: foo\r\nVersion: 1.2.3\r\nRemotes:\r\n    Open-Systems-Pharmacology/OSPSuite.RUtils,\r\n    Open-Systems-Pharmacology/TLF-Library\r\nAdditional_repositories: https://open-systems-pharmacology.r-universe.dev\r\nLicense: MIT\r\n' > "$DESC"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"REMOTES_ACTION=released"* ]]
  refute_grep -q '^Remotes:' "$DESC"
  [ "$(grep -c 'r-universe.dev' "$DESC")" = "1" ]
}

@test "release-remotes: an empty Remotes field is removed" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3" \
    "Remotes:" \
    "License: MIT"

  run "$SCRIPT" release-remotes "$DESC"

  [ "$status" -eq 0 ]
  refute_grep -q '^Remotes:' "$DESC"
  grep -q '^License: MIT$' "$DESC"
}

@test "detect-version: CRLF dev version is still a dev version" {
  printf 'Package: foo\r\nVersion: 1.2.3.9000\r\nLicense: MIT\r\n' > "$DESC"

  run "$SCRIPT" detect-version "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"IS_DEV_VERSION=true"* ]]
  [[ "$output" == *"PKG_VERSION=1.2.3.9000"* ]]
}

@test "dev-remotes: warns when a dev version lists an OSP R-universe itself" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes: Open-Systems-Pharmacology/OSPSuite.Plots" \
    "Additional_repositories: https://open-systems-pharmacology.r-universe.dev" \
    "License: MIT"

  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" == *"::warning title=R-universe on a dev version::"* ]]
}

@test "dev-remotes: no universe warning after a release round trip" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes: Open-Systems-Pharmacology/OSPSuite.Plots" \
    "License: MIT"

  "$SCRIPT" release-remotes "$DESC" >/dev/null 2>&1
  run "$SCRIPT" dev-remotes "$DESC"

  [ "$status" -eq 0 ]
  [[ "$output" != *"R-universe on a dev version"* ]]
}

@test "release then dev keeps two SSH git remotes apart" {
  write_desc \
    "Package: foo" \
    "Version: 1.2.3.9000" \
    "Remotes:" \
    "    git::git@bitbucket.org:team/pkgA.git," \
    "    git::git@bitbucket.org:team/pkgB.git," \
    "    Open-Systems-Pharmacology/OSPSuite.RUtils" \
    "License: MIT"
  cp "$DESC" "$TMPDIR/orig"

  "$SCRIPT" release-remotes "$DESC" >/dev/null 2>&1
  grep -q '^    git::git@bitbucket.org:team/pkgA.git,$' "$DESC"
  grep -q '^    git::git@bitbucket.org:team/pkgB.git,$' "$DESC"
  "$SCRIPT" dev-remotes "$DESC" >/dev/null 2>&1

  cmp -s "$DESC" "$TMPDIR/orig"
}

@test "refute_grep fails on a match and on a grep error" {
  printf 'abc\n' > "$TMPDIR/f"

  run refute_grep -q abc "$TMPDIR/f"
  [ "$status" -eq 1 ]
  run refute_grep -q abc "$TMPDIR/missing-file"
  [ "$status" -eq 1 ]
  run refute_grep -q xyz "$TMPDIR/f"
  [ "$status" -eq 0 ]
}
