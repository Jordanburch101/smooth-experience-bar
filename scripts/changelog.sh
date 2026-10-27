#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version, without its heading.
#
#   scripts/changelog.sh 1.0.0      (a leading "v" is dropped)
#
# Exits 1 if CHANGELOG.md has no "## <version>" section or it is empty, so a
# release never goes out without notes.
set -euo pipefail

version="${1:?usage: $0 <version>}"
version="${version#v}"
file="$(dirname "$0")/../CHANGELOG.md"

notes=$(awk -v v="$version" '
    /^## / { if (found) exit; found = ($2 == v); next }
    found { print }
' "$file" | sed -e '/./,$!d')

if [ -z "$(echo "$notes" | tr -d '[:space:]')" ]; then
    echo "CHANGELOG.md has no notes for $version. Add a \"## $version\" section." >&2
    exit 1
fi
printf '%s\n' "$notes"
