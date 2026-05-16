#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dry_run=0
list_only=0

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
elif [[ "${1:-}" == "--list" ]]; then
  list_only=1
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
  git -C "$repo_root" status --porcelain -- packages |
    sed -E 's/^...//' |
    awk -F/ '$1 == "packages" && NF >= 3 { print $2 }' |
    sort -u
}

version_pending_packages() {
  local package_dir package_name pkgver now_version_file now_version

  for package_dir in "${repo_root}"/packages/*; do
    [[ -d "$package_dir" ]] || continue
    [[ -f "${package_dir}/PKGBUILD" ]] || continue
    [[ -f "${package_dir}/.SRCINFO" ]] || continue

    package_name=$(basename "$package_dir")
    pkgver=$(pkgver_from_srcinfo "$package_dir")
    now_version_file="${package_dir}/NOW_VERSION"

    if [[ ! -f "$now_version_file" ]]; then
      printf '%s\n' "$package_name"
      continue
    fi

    now_version=$(tr -d '[:space:]' < "$now_version_file")
    if [[ "$now_version" != "$pkgver" ]]; then
      printf '%s\n' "$package_name"
    fi
  done
}

packages_to_push() {
  {
    changed_packages
    version_pending_packages
  } | sort -u
}

prepare_aur_worktree() {
  local pkgbase=$1
  local aur_dir=$2
  local remote_url="ssh://aur@aur.archlinux.org/${pkgbase}.git"
  local remote_heads
  local status

  mkdir -p "$aur_dir"
  git -C "$aur_dir" -c init.defaultBranch=master init
  git -C "$aur_dir" remote add origin "$remote_url"

  set +e
  remote_heads=$(git -C "$aur_dir" ls-remote --heads origin master 2>&1)
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    printf '%s\n' "$remote_heads" >&2
    die "could not access AUR remote for ${pkgbase}; check AUR_SSH_PRIVATE_KEY and AUR package permissions"
  fi

  if [[ -n "$remote_heads" ]]; then
    git -C "$aur_dir" pull --ff-only origin master
  else
    printf '%s has no remote master branch yet; preparing initial AUR push\n' "$pkgbase"
  fi
}

need_cmd awk
need_cmd git
need_cmd rsync
need_cmd sed
need_cmd tr

config_file="${repo_root}/config/VARS.sh"
if [[ -f "$config_file" ]]; then
  # shellcheck disable=SC1090
  source "$config_file"
fi

git_name=${NAME:-aur-auto-update}
git_email=${EMAIL:-aur-auto-update@users.noreply.github.com}

mapfile -t packages < <(packages_to_push)

if [[ "${#packages[@]}" -eq 0 ]]; then
  if [[ "$list_only" -eq 0 ]]; then
    printf 'no package changes to push to AUR\n'
  fi
  exit 0
fi

if [[ "$list_only" -eq 1 ]]; then
  printf '%s\n' "${packages[@]}"
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

  prepare_aur_worktree "$pkgbase" "$aur_dir"
  git -C "$aur_dir" config user.name "$git_name"
  git -C "$aur_dir" config user.email "$git_email"

  rsync_args=(
    -a
    --delete
    --exclude '.git'
    --exclude '.aurignore'
    --exclude 'update.sh'
    --exclude 'NOW_VERSION'
  )

  if [[ -f "${package_dir}/.aurignore" ]]; then
    rsync_args+=(--exclude-from "${package_dir}/.aurignore")
  fi

  rsync "${rsync_args[@]}" "${package_dir}/" "${aur_dir}/"

  if [[ -z "$(git -C "$aur_dir" status --porcelain)" ]]; then
    printf '%s has no AUR content changes after sync\n' "$pkgbase"
    printf '%s\n' "$pkgver" > "${package_dir}/NOW_VERSION"
    continue
  fi

  git -C "$aur_dir" add -A
  git -C "$aur_dir" commit -m "Update ${pkgbase} to ${pkgver}"
  git -C "$aur_dir" push origin master
  printf '%s\n' "$pkgver" > "${package_dir}/NOW_VERSION"
done
