#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

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
need_cmd sed
need_cmd sha256sum

[[ -f "$pkgbuild" ]] || die "PKGBUILD not found"

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

if [[ "$latest_ver" == "$pkgver" ]]; then
  printf '%s is already up to date (%s)\n' "$pkgname" "$pkgver"
  exit 0
fi

printf 'updating %s: %s -> %s\n' "$pkgname" "$pkgver" "$latest_ver"

update_assignment pkgver "$latest_ver"
update_assignment pkgrel 1

source_pkgbuild

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

for arch_name in "${arch[@]}"; do
  source_var="source_${arch_name}"
  sum_var="sha256sums_${arch_name}"

  if ! declare -p "$source_var" >/dev/null 2>&1; then
    printf 'skipping %s: %s is not defined\n' "$arch_name" "$source_var" >&2
    continue
  fi

  eval "source_entries=(\"\${${source_var}[@]}\")"
  [[ "${#source_entries[@]}" -eq 1 ]] || die "expected exactly one entry in ${source_var}"

  source_url=${source_entries[0]##*::}
  filename=${source_entries[0]%%::*}
  if [[ "$filename" == "$source_url" ]]; then
    filename=${source_url##*/}
  fi

  printf 'downloading %s\n' "$source_url"
  curl -fL --retry 3 --retry-delay 2 -o "${tmpdir}/${filename}" "$source_url"

  checksum=$(sha256sum "${tmpdir}/${filename}" | awk '{print $1}')
  update_sum_array "$sum_var" "$checksum"
  printf '%s = %s\n' "$sum_var" "$checksum"
done

if command -v makepkg >/dev/null 2>&1; then
  makepkg --printsrcinfo > .SRCINFO
  printf 'updated .SRCINFO\n'
else
  printf 'warning: makepkg not found; .SRCINFO was not updated\n' >&2
fi

printf 'done\n'
