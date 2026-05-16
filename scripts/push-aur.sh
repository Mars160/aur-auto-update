#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dry_run=0

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
fi

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

pkgbase_from_srcinfo() {
  awk -F ' = ' '/^pkgbase = / { print $2; exit }' "$1/.SRCINFO"
}

pkgver_from_srcinfo() {
  awk -F ' = ' '/^[[:space:]]*pkgver = / { print $2; exit }' "$1/.SRCINFO"
}

changed_packages() {
  git -C "$repo_root" diff --name-only -- packages |
    awk -F/ '$1 == "packages" && NF >= 3 { print $2 }' |
    sort -u
}

need_cmd awk
need_cmd git
need_cmd rsync

config_file="${repo_root}/config/VARS.sh"
if [[ -f "$config_file" ]]; then
  # shellcheck disable=SC1090
  source "$config_file"
fi

git_name=${NAME:-aur-auto-update}
git_email=${EMAIL:-aur-auto-update@users.noreply.github.com}

mapfile -t packages < <(changed_packages)

if [[ "${#packages[@]}" -eq 0 ]]; then
  printf 'no package changes to push to AUR\n'
  exit 0
fi

if [[ "$dry_run" -eq 1 ]]; then
  printf 'would push changed packages to AUR:\n'
  printf '  %s\n' "${packages[@]}"
  exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

for package_name in "${packages[@]}"; do
  package_dir="${repo_root}/packages/${package_name}"

  [[ -f "${package_dir}/PKGBUILD" ]] || die "PKGBUILD not found for ${package_name}"
  [[ -f "${package_dir}/.SRCINFO" ]] || die ".SRCINFO not found for ${package_name}"

  pkgbase=$(pkgbase_from_srcinfo "$package_dir")
  pkgver=$(pkgver_from_srcinfo "$package_dir")
  [[ -n "$pkgbase" ]] || die "could not read pkgbase from ${package_name}/.SRCINFO"
  [[ -n "$pkgver" ]] || die "could not read pkgver from ${package_name}/.SRCINFO"

  aur_dir="${tmpdir}/${pkgbase}"
  printf '==> pushing %s to AUR\n' "$pkgbase"

  git clone "ssh://aur@aur.archlinux.org/${pkgbase}.git" "$aur_dir"
  git -C "$aur_dir" config user.name "$git_name"
  git -C "$aur_dir" config user.email "$git_email"

  rsync_args=(
    -a
    --delete
    --exclude '.git'
    --exclude '.aurignore'
    --exclude 'update.sh'
  )

  if [[ -f "${package_dir}/.aurignore" ]]; then
    rsync_args+=(--exclude-from "${package_dir}/.aurignore")
  fi

  rsync "${rsync_args[@]}" "${package_dir}/" "${aur_dir}/"

  if [[ -z "$(git -C "$aur_dir" status --porcelain)" ]]; then
    printf '%s has no AUR content changes after sync\n' "$pkgbase"
    continue
  fi

  git -C "$aur_dir" add -A
  git -C "$aur_dir" commit -m "Update ${pkgbase} to ${pkgver}"
  git -C "$aur_dir" push origin master
done
