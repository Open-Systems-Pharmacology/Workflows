#!/usr/bin/env bash
# Manage the Version field and Remotes pinning in an R package DESCRIPTION file.
#
# Usage: manage_description.sh [DESCRIPTION_PATH]
#   DESCRIPTION_PATH defaults to ./DESCRIPTION
#
# Behavior:
#   - If Version is x.y.z.NNNN (4 components), bumps NNNN by 1 and removes @*release from Remotes.
#   - If Version is x.y.z (release), leaves Version untouched and adds @*release to entries in Remotes.
#
# Output:
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
# in the expected state (no actual edit applied).
#
# Exit codes: 0 on success; 1 on missing file or unparseable Version.

set -euo pipefail

description="${1:-DESCRIPTION}"

if [ ! -f "$description" ]; then
  echo "::error title=Missing DESCRIPTION::No DESCRIPTION file at '$description'" >&2
  exit 1
fi

version=$(grep '^Version:' "$description" | sed 's/^Version:[[:space:]]*//')
if [ -z "$version" ]; then
  echo "::error title=Invalid DESCRIPTION::Could not parse Version field from '$description'" >&2
  exit 1
fi
echo "Current version: $version" >&2

if [[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
  base="${BASH_REMATCH[1]}"
  dev=$((BASH_REMATCH[2] + 1))
  new_version="${base}.${dev}"
  echo "Dev version detected. Bumping: $version -> $new_version" >&2
  sed -i.bak "s/^Version:.*/Version: $new_version/" "$description" && rm -f "${description}.bak"
  echo "::notice title=Version bumped::Dev version $version -> $new_version" >&2
  is_dev=true
  final_version="$new_version"
else
  echo "Release version detected, no version bump needed." >&2
  echo "::notice title=Release version::Detected release version $version, no bump performed" >&2
  is_dev=false
  final_version="$version"
fi

extract_remotes_block() {
  awk '/^Remotes:/{in_r=1; print; next} in_r && /^[^ \t]/{exit} in_r{print}' "$1"
}

remotes_action=none
remotes_before=''
remotes_after=''

if grep -q '^Remotes:' "$description"; then
  remotes_before=$(extract_remotes_block "$description")

  if [ "$is_dev" = true ]; then
    awk '
      /^Remotes:/ { in_remotes=1; print; next }
      in_remotes && /^[^ \t]/ { in_remotes=0 }
      in_remotes { gsub(/@\*release/, ""); print; next }
      { print }
    ' "$description" > "${description}.tmp" && mv "${description}.tmp" "$description"
    intended_action=stripped
  else
    # Portable across BSD and GNU awk (no backreferences).
    # For each remotes entry without @*release, insert it before any trailing
    # comma/whitespace.
    awk '
      /^Remotes:/ { in_remotes=1; print; next }
      in_remotes && /^[^ \t]/ { in_remotes=0 }
      in_remotes {
        if ($0 !~ /@\*release/ && match($0, /[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+/)) {
          insert_at = RSTART + RLENGTH
          $0 = substr($0, 1, insert_at - 1) "@*release" substr($0, insert_at)
        }
        print; next
      }
      { print }
    ' "$description" > "${description}.tmp" && mv "${description}.tmp" "$description"
    intended_action=added
  fi

  remotes_after=$(extract_remotes_block "$description")

  if [ "$remotes_before" = "$remotes_after" ]; then
    remotes_action=unchanged
    if [ "$is_dev" = true ]; then version_kind="dev"; else version_kind="release"; fi
    echo "Remotes: already in expected state, no edit applied" >&2
    echo "::notice title=Remotes unchanged::Remotes already in expected state for ${version_kind} version" >&2
  else
    remotes_action="$intended_action"
    if [ "$intended_action" = stripped ]; then
      echo "Remotes: removed @*release" >&2
      echo "::notice title=Remotes updated::Removed @*release from Remotes (dev version)" >&2
    else
      echo "Remotes: added @*release" >&2
      echo "::notice title=Remotes updated::Added @*release to Remotes (release version)" >&2
    fi
  fi

  echo "Updated Remotes:" >&2
  printf '%s\n' "$remotes_after" >&2
else
  echo "No Remotes field found in DESCRIPTION" >&2
  echo "::notice title=No Remotes field::DESCRIPTION has no Remotes field, skipping remotes adjustment" >&2
fi

# base64 -w0 is GNU-only; fall back to `tr -d '\n'` to strip newlines portably.
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

echo "OLD_VERSION=$version"
echo "PKG_VERSION=$final_version"
echo "IS_DEV_VERSION=$is_dev"
echo "REMOTES_ACTION=$remotes_action"
echo "REMOTES_BEFORE_B64=$(b64 "$remotes_before")"
echo "REMOTES_AFTER_B64=$(b64 "$remotes_after")"
