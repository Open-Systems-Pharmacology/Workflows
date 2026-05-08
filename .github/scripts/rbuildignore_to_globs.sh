#!/usr/bin/env bash
# Translate .Rbuildignore (Perl regex, matched against relative paths) into
# glob patterns suitable for tj-actions/changed-files `files_ignore`.
#
# Usage: rbuildignore_to_globs.sh [.Rbuildignore_PATH]
#   defaults to ./.Rbuildignore
#
# Behavior:
#   Reads each non-empty, non-comment line and emits zero or more glob
#   patterns on stdout (one per line). If a pattern is too complex to
#   translate safely, it is skipped and a ::warning:: is written to stderr.
#
# Supported patterns:
#   ^name$          -> name  +  name/**     (top-level file or dir)
#   ^path/sub$      -> path/sub + path/sub/**
#   \.ext$          -> **/*.ext            (extension match anywhere)
#   name            -> **/name + **/name/**  (unanchored bare name)
#
# Anything containing unescaped regex metacharacters other than ^, $, and \.
# is skipped with a warning.

set -euo pipefail

rbuildignore="${1:-.Rbuildignore}"

if [ ! -f "$rbuildignore" ]; then
  # Missing .Rbuildignore is not an error: emit nothing.
  exit 0
fi

while IFS= read -r line || [ -n "$line" ]; do
  # Strip CR (Windows line endings) and surrounding whitespace.
  line="${line%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  # Skip blanks and comments.
  [ -z "$line" ] && continue
  case "$line" in \#*) continue ;; esac

  # Reject patterns that contain regex metacharacters we can't safely translate.
  # We allow: ^, $, \., and ordinary path characters.
  # First, temporarily strip the safe escapes to test the rest.
  stripped=$(printf '%s' "$line" | sed -e 's/\\\././g' -e 's/^\^//' -e 's/\$$//')
  case "$stripped" in
    *\**|*\?*|*\[*|*\]*|*\(*|*\)*|*\{*|*\}*|*\|*|*\+*|*\\*)
      echo "::warning title=rbuildignore_to_globs::Skipping unsupported pattern: ${line}" >&2
      continue
      ;;
  esac

  # Detect anchors on the *original* line.
  anchored_start=false
  anchored_end=false
  case "$line" in
    \^*) anchored_start=true ;;
  esac
  case "$line" in
    *\$) anchored_end=true ;;
  esac

  # Now we can safely use the stripped form as the path body.
  body="$stripped"
  [ -z "$body" ] && continue

  if $anchored_start && $anchored_end; then
    # ^foo$ -> foo + foo/**  (matches the path itself or anything under it)
    printf '%s\n' "$body"
    printf '%s/**\n' "$body"
  elif $anchored_end; then
    # \.ext$ -> **/*.ext  (extension or trailing-name match anywhere)
    case "$body" in
      .*) printf '**/*%s\n' "$body" ;;
      *)  printf '**/%s\n'  "$body"
          printf '**/%s/**\n' "$body" ;;
    esac
  elif $anchored_start; then
    # ^foo (no trailing $) -> foo* prefix match. Conservative: same as anchored both sides.
    printf '%s\n' "$body"
    printf '%s/**\n' "$body"
  else
    # Bare name, no anchors -> match anywhere.
    printf '**/%s\n' "$body"
    printf '**/%s/**\n' "$body"
  fi
done < "$rbuildignore"
