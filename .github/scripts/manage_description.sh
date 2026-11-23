#!/usr/bin/env bash
# Manage the Version field and the OSP dependency fields in an R package
# DESCRIPTION file.
#
# Usage: manage_description.sh <subcommand> [DESCRIPTION_PATH]
#   DESCRIPTION_PATH defaults to ./DESCRIPTION
#
# Subcommands:
#   detect-version  <desc> Classify dev vs release and emit the version outputs
#                          (IS_DEV_VERSION etc.) without mutating anything.
#   bump-version    <desc> Dev version x.y.z.NNNN -> bump trailing .NNNN by 1.
#                          Release version x.y.z  -> no-op. Never touches Remotes.
#   release-remotes <desc> Switch the OSP dependencies to their released builds
#                          on the R-universe (see "Dependency model"). Idempotent.
#   dev-remotes     <desc> Switch the OSP dependencies back to their development
#                          versions on GitHub (see "Dependency model"). Idempotent.
#
# Dependency model:
#   A dev version (x.y.z.NNNN) resolves its OSP dependencies from GitHub through
#   bare `Remotes:` entries (`org/repo`, `pkg=org/repo`). A release version
#   (x.y.z) resolves them from the R-universe of each GitHub owner
#   (https://<owner>.r-universe.dev), which builds the latest GitHub release.
#
#   release-remotes moves every remote out of `Remotes:` into
#   `Config/osp/dev-remotes:` (which R and pak ignore) and drops `Remotes:`: a
#   release has no Remotes field. For a GitHub remote of an owner in
#   UNIVERSE_OWNERS (OSP, esqLABS), it adds the owner's R-universe to
#   `Additional_repositories:`. The URLs it adds (and only those) are recorded
#   in `Config/osp/release-repositories:`. Any other remote (another owner, a
#   non-GitHub source such as `url::`) gets a warning: the release must then
#   find that package in a repository. An explicit ref (`@v2.0.0`) is not kept
#   either: the release uses the version that the R-universe builds.
#
#   dev-remotes moves the `Config/osp/dev-remotes:` entries back into
#   `Remotes:`, strips any legacy `@*release` ref, and removes the URLs listed
#   in `Config/osp/release-repositories:` from `Additional_repositories:`. A
#   repository the package listed itself stays.
#
#   Only `Remotes:` entries are concerned. CRAN dependencies are untouched.
#
# A subcommand is required. The workflows that use them:
#   - sync-remotes.yaml runs release-remotes on a release version and
#     dev-remotes on a dev version, in the PR.
#   - release-pr.yaml runs release-remotes; dev-pr.yaml runs dev-remotes.
#   - R-CMD-check-released-deps.yaml runs release-remotes ephemerally.
#   - bump-dev-version.yaml bumps the dev version on push to main (bump-version).
#   - publish-release.yaml tags release versions (detect-version).
#
# Output (all subcommands):
#   stdout: key=value lines suitable for `>> "$GITHUB_OUTPUT"` (or $GITHUB_ENV):
#     OLD_VERSION=<version before any change>
#     PKG_VERSION=<version after the (possible) bump>
#     IS_DEV_VERSION=<true|false>
#     REMOTES_ACTION=<released|restored|unchanged|none>
#     REMOTES_BEFORE_B64=<base64 of the dependency fields before>
#     REMOTES_AFTER_B64=<base64 of the dependency fields after>
#   stderr: human-readable diagnostics and ::notice::/::warning::/::error::
#   annotations.
#
# The "dependency fields" are the `Remotes:`, `Config/osp/dev-remotes:`,
# `Config/osp/release-repositories:` and `Additional_repositories:` blocks, base64-encoded so multi-line blocks survive
# transport through $GITHUB_OUTPUT. REMOTES_ACTION=none means there was nothing
# to switch (no tracking remote, no stored dev remote); unchanged means the
# fields were already in the expected state. Subcommands that never touch the
# dependency fields (detect-version, bump-version) report none.
#
# Exit codes: 0 on success; 1 on missing file or unparseable Version.

set -euo pipefail

DEV_FIELD='Config/osp/dev-remotes'
ADDED_FIELD='Config/osp/release-repositories'
REPOS_FIELD='Additional_repositories'
# GitHub owners (lowercase) whose R-universe builds their latest GitHub release.
UNIVERSE_OWNERS='open-systems-pharmacology esqlabs'

# --- DCF field helpers -------------------------------------------------------
# A field is its `Name:` line plus the indented continuation lines that follow.

has_field() {
  awk -v f="$2:" 'index($0, f) == 1 { found = 1; exit } END { exit !found }' "$1"
}

field_block() {
  awk -v f="$2:" '
    index($0, f) == 1 { in_f = 1; print; next }
    in_f && /^[^ \t]/ { exit }
    in_f { print }
  ' "$1"
}

# One entry per line. Entries are comma- and/or whitespace-separated. Carriage
# returns are dropped, for a DESCRIPTION checked out with CRLF on Windows.
field_entries() {
  field_block "$1" "$2" | tr -d '\r' | sed '1s/^[^:]*://' | tr ',\t ' '\n\n\n' | sed '/^$/d'
}

remove_field() {
  awk -v f="$2:" '
    index($0, f) == 1 { in_f = 1; next }
    in_f && /^[ \t]/ { next }
    { in_f = 0; print }
  ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# set_field <desc> <field> <anchor> [entry...]
# Writes the field in place when present, else right after the anchor field's
# block, else at the end of the file. With no entries, removes the field.
set_field() {
  local desc="$1" field="$2" anchor="$3"
  shift 3
  if [ "$#" -eq 0 ]; then
    remove_field "$desc" "$field"
    return
  fi
  local block i=0
  block="$field:"
  for e in "$@"; do
    i=$((i + 1))
    if [ "$i" -lt "$#" ]; then block+=$'\n'"    $e,"; else block+=$'\n'"    $e"; fi
  done
  local present=0
  has_field "$desc" "$field" && present=1
  BLOCK="$block" awk -v f="$field:" -v a="$anchor:" -v present="$present" '
    {
      if (in_f) { if (/^[ \t]/) next; in_f = 0 }
      if (in_a && !/^[ \t]/) { print ENVIRON["BLOCK"]; in_a = 0; done = 1 }
      if (index($0, f) == 1) {
        if (!done) { print ENVIRON["BLOCK"]; done = 1 }
        in_f = 1; next
      }
      if (!present && !done && a != ":" && index($0, a) == 1) in_a = 1
      print
    }
    END {
      if (in_a) { print ENVIRON["BLOCK"]; done = 1 }
      if (!done) print ENVIRON["BLOCK"]
    }
  ' "$desc" > "$desc.tmp" && mv "$desc.tmp" "$desc"
}

# --- remote entry helpers ----------------------------------------------------

# Entry without its ref, used to match the same remote across fields.
remote_id() {
  local e="${1%%@*}"
  printf '%s' "${e%%#*}"
}

# GitHub `org/repo` part of an entry (no `pkg=` or `github::` prefix), or
# nothing for a non-GitHub source (`url::`, `git::`, `local::`, ...).
github_spec() {
  local s="$1"
  case "$s" in
    *=*) s="${s#*=}" ;;
  esac
  s="${s#github::}"
  case "$s" in
    *::*) return ;;
    */*) printf '%s' "$s" ;;
  esac
}

# True for a GitHub remote whose owner has an R-universe (UNIVERSE_OWNERS).
has_universe() {
  local spec owner
  spec="$(github_spec "$1")"
  [ -n "$spec" ] || return 1
  owner="$(printf '%s' "${spec%%/*}" | tr '[:upper:]' '[:lower:]')"
  case " $UNIVERSE_OWNERS " in
    *" $owner "*) return 0 ;;
  esac
  return 1
}

universe_url() {
  local spec owner
  spec="$(github_spec "$1")"
  owner="$(printf '%s' "${spec%%/*}" | tr '[:upper:]' '[:lower:]')"
  printf 'https://%s.r-universe.dev' "$owner"
}

normalize_url() {
  printf '%s' "${1%/}" | tr '[:upper:]' '[:lower:]'
}

# Read a field's entries into the global array `entries` (no namerefs, so the
# script also runs on the bash 3.2 that ships with macOS).
read_entries() {
  entries=()
  local line
  while IFS= read -r line; do entries+=("$line"); done < <(field_entries "$1" "$2")
}

# --- shared helpers ----------------------------------------------------------

dependency_fields() {
  field_block "$1" Remotes
  field_block "$1" "$DEV_FIELD"
  field_block "$1" "$ADDED_FIELD"
  field_block "$1" "$REPOS_FIELD"
}

# base64 -w0 is GNU-only; fall back to `tr -d '\n'` to strip newlines portably.
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

# Read and validate the DESCRIPTION path + Version field. Populates the
# globals `version` and `description`. Exits 1 on error.
load_description() {
  description="$1"
  if [ ! -f "$description" ]; then
    echo "::error title=Missing DESCRIPTION::No DESCRIPTION file at '$description'" >&2
    exit 1
  fi
  # `|| true`: with `set -o pipefail`, a missing Version line makes grep exit 1
  # and would abort the script before the guard below can emit the annotation.
  version=$(grep '^Version:' "$description" | sed 's/^Version:[[:space:]]*//' || true)
  if [ -z "$version" ]; then
    echo "::error title=Invalid DESCRIPTION::Could not parse Version field from '$description'" >&2
    exit 1
  fi
  echo "Current version: $version" >&2
}

# Determine dev vs release from the loaded `version`. Populates `is_dev` and
# `final_version`. Bumps the trailing component in place when `$1` is "bump".
classify_version() {
  local do_bump="$1"
  if [[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
    is_dev=true
    if [ "$do_bump" = bump ]; then
      local base="${BASH_REMATCH[1]}"
      local dev=$((BASH_REMATCH[2] + 1))
      final_version="${base}.${dev}"
      echo "Dev version detected. Bumping: $version -> $final_version" >&2
      sed -i.bak "s/^Version:.*/Version: $final_version/" "$description" && rm -f "${description}.bak"
    else
      final_version="$version"
      echo "Dev version detected." >&2
    fi
  else
    is_dev=false
    final_version="$version"
    echo "Release version detected, no version bump needed." >&2
    if [ "$do_bump" = bump ]; then
      echo "::notice title=Release version::Detected release version $version, no bump performed" >&2
    fi
  fi
}

no_remotes_work() {
  remotes_action=none
  remotes_before=''
  remotes_after=''
}

# --- dependency transforms ---------------------------------------------------

# Moves all remotes to DEV_FIELD, drops Remotes, and adds the R-universes.
to_release() {
  local desc="$1"
  local remotes=() stored=() repos=() added=() e
  read_entries "$desc" Remotes
  remotes=(${entries[@]+"${entries[@]}"})
  read_entries "$desc" "$DEV_FIELD"
  stored=(${entries[@]+"${entries[@]}"})
  read_entries "$desc" "$REPOS_FIELD"
  repos=(${entries[@]+"${entries[@]}"})
  read_entries "$desc" "$ADDED_FIELD"
  added=(${entries[@]+"${entries[@]}"})

  local track=()
  for e in ${remotes[@]+"${remotes[@]}"}; do track+=("${e%@\*release}"); done

  # Stored entries first, then newly moved ones not already stored.
  local all=(${stored[@]+"${stored[@]}"}) s dup
  for e in ${track[@]+"${track[@]}"}; do
    dup=false
    for s in ${all[@]+"${all[@]}"}; do
      [ "$(remote_id "$s")" = "$(remote_id "$e")" ] && dup=true
    done
    $dup || all+=("$e")
  done
  [ "${#all[@]}" -eq 0 ] && return

  local new_repos=(${repos[@]+"${repos[@]}"}) url r
  for e in "${all[@]}"; do
    has_universe "$e" || continue
    url="$(universe_url "$e")"
    dup=false
    for r in ${new_repos[@]+"${new_repos[@]}"}; do
      [ "$(normalize_url "$r")" = "$(normalize_url "$url")" ] && dup=true
    done
    if ! $dup; then
      new_repos+=("$url")
      added+=("$url")
    fi
  done

  if [ "${#track[@]}" -gt 0 ]; then
    set_field "$desc" "$DEV_FIELD" Remotes "${all[@]}"
    remove_field "$desc" Remotes
  fi
  if [ "${#new_repos[@]}" -ne "${#repos[@]}" ]; then
    set_field "$desc" "$REPOS_FIELD" "$DEV_FIELD" "${new_repos[@]}"
    set_field "$desc" "$ADDED_FIELD" "$DEV_FIELD" "${added[@]}"
  fi

  # The release resolves these from a repository, not from their remote.
  for e in "${all[@]}"; do
    if ! has_universe "$e"; then
      echo "::warning title=No R-universe for remote::'$e' is not from an owner with an R-universe ($UNIVERSE_OWNERS); the release must find this package in another repository" >&2
    else
      case "${e%@\*release}" in
        *@* | *#*) echo "::notice title=Remote ref dropped::'$e' has an explicit ref; the release uses the version that the R-universe builds" >&2 ;;
      esac
    fi
  done
}

# Moves DEV_FIELD entries back to Remotes, strips legacy @*release refs, and
# removes the repositories that to_release added.
to_dev() {
  local desc="$1"
  local remotes=() stored=() repos=() added=() e s r dup
  read_entries "$desc" Remotes
  remotes=(${entries[@]+"${entries[@]}"})
  read_entries "$desc" "$DEV_FIELD"
  stored=(${entries[@]+"${entries[@]}"})
  read_entries "$desc" "$REPOS_FIELD"
  repos=(${entries[@]+"${entries[@]}"})
  read_entries "$desc" "$ADDED_FIELD"
  added=(${entries[@]+"${entries[@]}"})

  if [ "${#added[@]}" -gt 0 ]; then
    local kept_repos=()
    for r in ${repos[@]+"${repos[@]}"}; do
      dup=false
      for s in "${added[@]}"; do
        [ "$(normalize_url "$r")" = "$(normalize_url "$s")" ] && dup=true
      done
      $dup || kept_repos+=("$r")
    done
    if [ "${#kept_repos[@]}" -ne "${#repos[@]}" ]; then
      set_field "$desc" "$REPOS_FIELD" '' ${kept_repos[@]+"${kept_repos[@]}"}
    fi
    remove_field "$desc" "$ADDED_FIELD"
  fi

  local all=()
  for e in ${remotes[@]+"${remotes[@]}"}; do all+=("${e%@\*release}"); done
  for s in ${stored[@]+"${stored[@]}"}; do
    dup=false
    for e in ${all[@]+"${all[@]}"}; do
      [ "$(remote_id "$s")" = "$(remote_id "$e")" ] && dup=true
    done
    $dup || all+=("$s")
  done
  [ "${#all[@]}" -eq 0 ] && return

  # Rewrite Remotes only when its entries change, to keep the user's layout.
  local before=''
  [ "${#remotes[@]}" -gt 0 ] && before="${remotes[*]}"
  if [ "${all[*]}" != "$before" ]; then
    set_field "$desc" Remotes "$DEV_FIELD" "${all[@]}"
  fi
  remove_field "$desc" "$DEV_FIELD"
}

# transform_dependencies <to_release|to_dev> <action name>
transform_dependencies() {
  local transform="$1" intended_action="$2"
  remotes_before=$(dependency_fields "$description")
  "$transform" "$description"
  remotes_after=$(dependency_fields "$description")

  if [ "$remotes_before" != "$remotes_after" ]; then
    remotes_action="$intended_action"
    echo "::notice title=Dependencies updated::OSP dependency fields ${intended_action} (see the step log for the new fields)" >&2
  elif ! has_field "$description" Remotes && ! has_field "$description" "$DEV_FIELD" && ! has_field "$description" "$ADDED_FIELD"; then
    remotes_action=none
    echo "::notice title=No Remotes field::DESCRIPTION has no Remotes, nothing to switch" >&2
  else
    remotes_action=unchanged
    echo "::notice title=Dependencies unchanged::Dependency fields already in expected state" >&2
  fi

  echo "Dependency fields after:" >&2
  printf '%s\n' "$remotes_after" >&2
}

# Emit the stdout key=value contract. Reads the populated globals.
emit_outputs() {
  echo "OLD_VERSION=$version"
  echo "PKG_VERSION=$final_version"
  echo "IS_DEV_VERSION=$is_dev"
  echo "REMOTES_ACTION=$remotes_action"
  echo "REMOTES_BEFORE_B64=$(b64 "$remotes_before")"
  echo "REMOTES_AFTER_B64=$(b64 "$remotes_after")"
}

# --- subcommands -------------------------------------------------------------

# Classify the version without mutating anything. Emits the version outputs
# only (no Remotes work), so a workflow can gate on IS_DEV_VERSION cheaply and
# share this script's single dev/release regex.
cmd_detect_version() {
  load_description "$1"
  classify_version nobump
  no_remotes_work
  emit_outputs
}

cmd_bump_version() {
  load_description "$1"
  classify_version bump
  no_remotes_work
  emit_outputs
}

cmd_release_remotes() {
  load_description "$1"
  classify_version nobump
  transform_dependencies to_release released
  emit_outputs
}

cmd_dev_remotes() {
  load_description "$1"
  classify_version nobump
  transform_dependencies to_dev restored
  emit_outputs
}

# --- dispatch ----------------------------------------------------------------

usage() {
  echo "::error title=Unknown subcommand::Usage: manage_description.sh {detect-version|bump-version|release-remotes|dev-remotes} [DESCRIPTION]" >&2
  exit 2
}

subcommand="${1:-}"
case "$subcommand" in
  detect-version)  cmd_detect_version "${2:-DESCRIPTION}" ;;
  bump-version)    cmd_bump_version "${2:-DESCRIPTION}" ;;
  release-remotes) cmd_release_remotes "${2:-DESCRIPTION}" ;;
  dev-remotes)     cmd_dev_remotes "${2:-DESCRIPTION}" ;;
  *)               usage ;;
esac
