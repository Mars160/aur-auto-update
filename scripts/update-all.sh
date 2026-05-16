#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
packages_dir="${repo_root}/packages"

[[ -d "$packages_dir" ]] || {
  printf 'error: packages directory not found: %s\n' "$packages_dir" >&2
  exit 1
}

found=0

for package_dir in "${packages_dir}"/*; do
  [[ -d "$package_dir" ]] || continue
  [[ -f "${package_dir}/PKGBUILD" ]] || continue

  found=1
  package_name=$(basename "$package_dir")
  update_script="${package_dir}/update.sh"

  if [[ ! -f "$update_script" ]]; then
    printf 'warning: skipping %s; update.sh not found\n' "$package_name" >&2
    continue
  fi

  printf '==> checking %s\n' "$package_name"
  (
    cd "$package_dir"
    bash ./update.sh
  )
done

[[ "$found" -eq 1 ]] || {
  printf 'error: no package directories with PKGBUILD found under %s\n' "$packages_dir" >&2
  exit 1
}
