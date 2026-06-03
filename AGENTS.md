# Repository Guidelines

## Project Structure & Module Organization

This repository automates AUR package updates and publishing.

- `scripts/` contains repository-level automation. `update-all.sh` runs every package updater; `push-aur.sh` syncs changed packages to AUR remotes.
- `config/VARS.sh` provides maintainer metadata used by scripts (`NAME`, `EMAIL`).
- `packages/<pkgname>/` contains one AUR package. Each package should include `PKGBUILD`, `.SRCINFO`, `NOW_VERSION`, and `update.sh`.

Keep package-specific logic inside its package directory. Shared behavior belongs in `scripts/`.

## Build, Test, and Development Commands

- `bash scripts/update-all.sh`: runs `update.sh` for each package directory with a `PKGBUILD`.
- `bash packages/openhuman-core-bin/update.sh`: checks the upstream GitHub release, updates checksums, and regenerates `.SRCINFO` when `makepkg` is installed.
- `bash scripts/push-aur.sh --list`: prints packages that have pending local changes or a `NOW_VERSION` mismatch.
- `bash scripts/push-aur.sh --dry-run`: shows what would be pushed without touching AUR.
- `bash scripts/push-aur.sh`: pushes changed package contents to AUR and updates `NOW_VERSION`.

Use `GITHUB_TOKEN` for repeated GitHub API calls. AUR publishing requires working SSH credentials and package permissions.

## Coding Style & Naming Conventions

Scripts are Bash and should use `#!/usr/bin/env bash` with `set -euo pipefail`. Prefer lowercase `snake_case` for variables and functions, quote expansions, and report failures with short `error:` messages to stderr. Name package directories after the AUR package, for example `packages/openhuman-core-bin/`.

PKGBUILD files should follow Arch conventions: lowercase package variables, arrays for dependencies and checksums, and architecture-specific `source_<arch>` / `sha256sums_<arch>` pairs when needed.

## Testing Guidelines

There is no separate test suite. Validate changes by running the narrowest relevant script first, then the full updater:

- `bash packages/<pkgname>/update.sh`
- `bash scripts/update-all.sh`
- `bash scripts/push-aur.sh --dry-run`

When editing shell scripts, run `shellcheck` if available. For package changes, ensure `.SRCINFO` matches `PKGBUILD` with `makepkg --printsrcinfo > .SRCINFO` from the package directory.

## Commit & Pull Request Guidelines

Recent commits use concise Conventional Commit-style messages, mainly `chore: update AUR packages` and `fix: ...`. Keep the subject imperative and specific, for example `fix: handle missing .SRCINFO`.

Pull requests should include affected package names, commands run, and whether AUR publishing was dry-run or completed. Link related issues when available. Include output snippets for version bumps, checksum changes, or publishing failures.

## Security & Configuration Tips

Do not commit private keys, tokens, or generated temporary worktrees. `config/VARS.sh` is for maintainer identity only. Provide secrets through the environment, such as `GITHUB_TOKEN` or AUR SSH configuration.
