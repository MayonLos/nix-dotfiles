#!/usr/bin/env bash
set -euo pipefail

theme=$1
palette_blue=$2

# The locked Papirus blue folder artwork uses these source colors for its
# shaded face and main fill. Change only named blue folder variants, leaving
# unrelated application icons and all geometry intact.
while IFS= read -r -d '' icon; do
  sed -i \
    -e "s/#4877b1/${palette_blue}/g" \
    -e "s/#5294e2/${palette_blue}/g" \
    "$icon"
done < <(find "$theme" -path '*/places/*' -type f \
  \( -name 'folder-blue*.svg' -o -name 'user-blue*.svg' \) -print0)
