#!/usr/bin/env bash
# Manage the Version field and Remotes pinning in an R package DESCRIPTION file.
#
# Usage: manage_description.sh <subcommand> [DESCRIPTION_PATH]
#   DESCRIPTION_PATH defaults to ./DESCRIPTION
#
# Subcommands:
#   detect-version <desc> Classify dev vs release and emit the version outputs
#                         (IS_DEV_VERSION etc.) without mutating anything.
#   bump-version <desc>   Dev version x.y.z.NNNN -> bump trailing .NNNN by 1.
#                         Release version x.y.z  -> no-op. Never touches Remotes.
#   pin-remotes  <desc>   Strip any existing @<ref> suffix from each remote
#                         entry, then append @*release. Idempotent.
#   unpin-remotes <desc>  Strip @*release from each remote entry. Idempotent.
#
# A subcommand is required. The responsibilities these subcommands serve are
# split across three workflows (see docs/description-tagging-rethink.md):
#   - sync-remotes.yaml syncs Remotes in the PR (pin-remotes on a release
#     version, unpin-remotes on a dev version).
#   - bump-dev-version.yaml bumps the dev version on push to main (bump-version).
#   - publish-release.yaml tags release versions and publishes a GitHub Release
#     (detect-version).
#
# Output (all subcommands):
#   stdout: key=value lines suitable for `>> "$GITHUB_OUTPUT"` (or $GITHUB_ENV):
#     OLD_VERSION=<version before any change>
#     PKG_VERSION=<version after the (possible) bump>
#     IS_DEV_VERSION=<true|false>
#     REMOTES_ACTION=<stripped|added|unchanged|none>
#     REMOTES_BEFORE_B64=<base64 of Remotes block before>
#     REMOTES_AFTER_B64=<base64 of Remotes block after>
#   stderr: human-readable diagnostics and ::notice::/::error:: annotations.
#
# REMOTES_BEFORE_B64 / REMOTES_AFTER_B64 are base64-encoded so multi-line
# Remotes blocks survive transport through $GITHUB_OUTPUT. If the Remotes
# field is absent, REMOTES_ACTION=none and both blobs are empty.
# REMOTES_ACTION=unchanged means the Remotes field was present but was already
# in the expected state (no actual edit applied). Subcommands that never touch
# Remotes (bump-version) report REMOTES_ACTION=none.
#
# Exit codes: 0 on success; 1 on missing file or unparseable Version.

set -euo pipefail

# --- shared helpers ----------------------------------------------------------

# Extract the Remotes block (the `Remotes:` line plus its indented continuation
# lines, stopping at the next top-level field).
extract_remotes_block() {
  awk '/^Remotes:/{in_r=1; print; next} in_r && /^[^ \t]/{exit} in_r{print}' "$1"
}

# Strip existing @<ref> suffix from each remote entry, then append @*release.
# Idempotent: re-running yields the same result. Operates in place.
pin() {
  local desc="$1"
  awk '
    /^Remotes:/ { in_remotes=1; print; next }
    in_remotes && /^[^ \t]/ { in_remotes=0 }
    in_remotes {
      # Remove existing @ref suffix, then append @*release to each org/repo.
      gsub(/@[^,]*/, "")
      gsub(/([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)/, "&@*release")
      print; next
    }
    { print }
  ' "$desc" > "${desc}.tmp" && mv "${desc}.tmp" "$desc"
}

# Remove @*release from each remote entry. Operates in place.
unpin() {
  local desc="$1"
  awk '
    /^Remotes:/ { in_remotes=1; print; next }
    in_remotes && /^[^ \t]/ { in_remotes=0 }
    in_remotes { gsub(/@\*release/, ""); print; next }
    { print }
  ' "$desc" > "${desc}.tmp" && mv "${desc}.tmp" "$desc"
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

# Apply a Remotes transform (`pin` or `unpin`) and set REMOTES_ACTION /
# before/after blobs. Populates the globals `remotes_action`,
# `remotes_before`, `remotes_after`. `$1` = transform fn, `$2` = the action
# name reported when an edit actually changed the block.
transform_remotes() {
  local transform="$1" intended_action="$2"
  remotes_action=none
  remotes_before=''
  remotes_after=''

  if ! grep -q '^Remotes:' "$description"; then
    echo "No Remotes field found in DESCRIPTION" >&2
    echo "::notice title=No Remotes field::DESCRIPTION has no Remotes field, skipping remotes adjustment" >&2
    return
  fi

  remotes_before=$(extract_remotes_block "$description")
  "$transform" "$description"
  remotes_after=$(extract_remotes_block "$description")

  if [ "$remotes_before" = "$remotes_after" ]; then
    remotes_action=unchanged
    echo "Remotes: already in expected state, no edit applied" >&2
    echo "::notice title=Remotes unchanged::Remotes already in expected state" >&2
  else
    remotes_action="$intended_action"
    if [ "$intended_action" = stripped ]; then
      echo "Remotes: removed @*release" >&2
      echo "::notice title=Remotes updated::Removed @*release from Remotes" >&2
    else
      echo "Remotes: added @*release" >&2
      echo "::notice title=Remotes updated::Added @*release to Remotes" >&2
    fi
  fi

  echo "Updated Remotes:" >&2
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
  remotes_action=none
  remotes_before=''
  remotes_after=''
  emit_outputs
}

cmd_bump_version() {
  load_description "$1"
  classify_version bump
  remotes_action=none
  remotes_before=''
  remotes_after=''
  emit_outputs
}

cmd_pin_remotes() {
  load_description "$1"
  classify_version nobump
  transform_remotes pin added
  emit_outputs
}

cmd_unpin_remotes() {
  load_description "$1"
  classify_version nobump
  transform_remotes unpin stripped
  emit_outputs
}

# --- dispatch ----------------------------------------------------------------

usage() {
  echo "::error title=Unknown subcommand::Usage: manage_description.sh {detect-version|bump-version|pin-remotes|unpin-remotes} [DESCRIPTION]" >&2
  exit 2
}

subcommand="${1:-}"
case "$subcommand" in
  detect-version) cmd_detect_version "${2:-DESCRIPTION}" ;;
  bump-version)  cmd_bump_version "${2:-DESCRIPTION}" ;;
  pin-remotes)   cmd_pin_remotes "${2:-DESCRIPTION}" ;;
  unpin-remotes) cmd_unpin_remotes "${2:-DESCRIPTION}" ;;
  *)             usage ;;
esac
