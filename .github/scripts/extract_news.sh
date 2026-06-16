#!/usr/bin/env bash
# Extract the NEWS.md section for a given package version.
#
# Mirrors what usethis::use_github_release() does when it pulls release notes
# from NEWS.md, but for non-interactive CI: print the body of the section whose
# heading mentions the requested version, so it can feed `gh release create
# --notes-file`.
#
# Usage: extract_news.sh <version> [NEWS_PATH]
#   NEWS_PATH defaults to ./NEWS.md
#
# Behaviour:
#   - Finds the FIRST Markdown heading (#, ##, ### ...) whose text contains the
#     exact <version> as a whole token (e.g. "# pkg 1.2.3", "## 1.2.3",
#     "# pkg 1.2.3.9000"). The match is anchored on word boundaries so 1.2.3
#     does not match 1.2.30.
#   - Prints every line AFTER that heading, up to (but excluding) the next
#     heading at the same or a higher level (fewer-or-equal '#'). Leading and
#     trailing blank lines are trimmed.
#   - Exit 0 and print the section when found.
#   - Exit 0 and print NOTHING when NEWS.md is missing or has no matching
#     section (callers supply their own fallback notes). A diagnostic goes to
#     stderr so the reason is visible in logs.
#
# Output: the section body on stdout; diagnostics on stderr.

set -euo pipefail

version="${1:-}"
news="${2:-NEWS.md}"

if [ -z "$version" ]; then
  echo "::error title=Missing version::extract_news.sh requires a version argument" >&2
  exit 2
fi

if [ ! -f "$news" ]; then
  echo "No NEWS file at '$news'; emitting empty notes." >&2
  exit 0
fi

# awk does the work in one pass:
#   - VER is the literal version; we build a word-boundary-ish match by checking
#     the heading text token-by-token (split on non-version characters).
#   - On the first heading whose text contains VER as a whole token, record its
#     level (number of leading '#') and start capturing.
#   - Stop capturing at the next heading whose level <= the section level.
section=$(awk -v ver="$version" '
  function heading_level(line,    n) {
    # count leading # characters
    n = 0
    while (substr(line, n + 1, 1) == "#") n++
    return n
  }
  function heading_has_version(line,    rest, i, k, parts) {
    # strip leading #s and spaces, then split on characters that cannot be part
    # of a version token so "1.2.3" is compared whole (not as a substring of
    # "1.2.30").
    rest = line
    sub(/^#+[[:space:]]*/, "", rest)
    k = split(rest, parts, /[^0-9A-Za-z._-]+/)
    for (i = 1; i <= k; i++) {
      if (parts[i] == ver) return 1
    }
    return 0
  }
  /^#/ {
    lvl = heading_level($0)
    if (!capturing) {
      if (heading_has_version($0)) {
        capturing = 1
        sec_level = lvl
        next
      }
    } else if (lvl <= sec_level) {
      # next section at same/higher level ends the capture
      exit
    }
  }
  capturing { print }
' "$news")

# Trim leading/trailing blank lines.
section=$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

if [ -z "$section" ]; then
  echo "No NEWS.md section found for version '$version'; emitting empty notes." >&2
  exit 0
fi

printf '%s\n' "$section"
