#!/usr/bin/env bash
set -euo pipefail

package_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "${package_dir}/../.." && pwd)

cd "$package_dir"

pkgbuild="PKGBUILD"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

curl_json() {
  local api_url=$1
  local curl_args=(-fsSL)

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  curl "${curl_args[@]}" "$api_url"
}

update_assignment() {
  local key=$1
  local value=$2

  sed -i -E "s|^${key}=.*|${key}=${value}|" "$pkgbuild"
}

update_maintainer() {
  [[ -n "${NAME:-}" && -n "${EMAIL:-}" ]] || return 0

  local maintainer="# Maintainer: ${NAME} <${EMAIL}>"

  if grep -q '^# Maintainer:' "$pkgbuild"; then
    sed -i -E "s|^# Maintainer:.*|${maintainer}|" "$pkgbuild"
  else
    sed -i "1i${maintainer}" "$pkgbuild"
  fi
}

update_sum_array() {
  local key=$1
  local value=$2

  sed -i -E "s|^(${key}=\\().*(\\))$|\\1'${value}'\\2|" "$pkgbuild"
}

source_pkgbuild() {
  # shellcheck disable=SC1091
  source "./${pkgbuild}"
}

need_cmd curl
need_cmd grep
need_cmd sed
need_cmd sha256sum

[[ -f "$pkgbuild" ]] || die "PKGBUILD not found"

if [[ -f "${repo_root}/config/VARS.sh" ]]; then
  # shellcheck disable=SC1091
  source "${repo_root}/config/VARS.sh"
fi

update_maintainer
source_pkgbuild

repo=${url#https://github.com/}
repo=${repo%.git}
repo=${repo%/}
[[ "$repo" != "$url" && "$repo" == */* ]] || die "PKGBUILD url is not a GitHub repository: ${url}"

release_json=$(curl_json "https://api.github.com/repos/${repo}/releases/latest")
latest_tag=$(
  printf '%s\n' "$release_json" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
)
[[ -n "$latest_tag" ]] || die "could not read latest release tag from GitHub"

latest_ver=${latest_tag#v}
[[ -n "$latest_ver" ]] || die "latest release tag is empty: ${latest_tag}"

asset_url="${url}/releases/download/${latest_tag}/${_upstream_name}.zip"

if [[ "$latest_ver" == "$pkgver" ]]; then
  printf '%s is already up to date (%s)\n' "$pkgname" "$pkgver"
else
  printf 'updating %s: %s -> %s\n' "$pkgname" "$pkgver" "$latest_ver"
  update_assignment pkgver "$latest_ver"
  update_assignment pkgrel 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

printf 'downloading %s\n' "$asset_url"
curl -fL --retry 3 --retry-delay 2 -o "${tmpdir}/${_upstream_name}.zip" "$asset_url"

checksum=$(sha256sum "${tmpdir}/${_upstream_name}.zip" | awk '{print $1}')
update_sum_array sha256sums "$checksum"
printf 'sha256sums = %s\n' "$checksum"

if command -v makepkg >/dev/null 2>&1; then
  makepkg --printsrcinfo > .SRCINFO
  printf 'updated .SRCINFO\n'
else
  printf 'warning: makepkg not found; .SRCINFO was not updated\n' >&2
fi

printf 'done\n'
