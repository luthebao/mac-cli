#!/usr/bin/env bash
# mac-cli installer. Downloads the latest GitHub release tarball and drops the
# binary into the first writable directory on $PATH (or ~/.local/bin).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/luthebao/mac-cli/main/install.sh | bash
#
# Env overrides:
#   VERSION   pin a specific release (e.g. VERSION=0.2.0)
#   PREFIX    install dir (default: /usr/local/bin if writable, else ~/.local/bin)
#   REPO      override source repo (default: luthebao/mac-cli)

set -euo pipefail

REPO="${REPO:-luthebao/mac-cli}"
VERSION="${VERSION:-}"
PREFIX="${PREFIX:-}"

log() { printf 'install: %s\n' "$*"; }
err() { printf 'install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || err "mac-cli currently only supports macOS"

arch="$(uname -m)"
case "$arch" in
  arm64|aarch64) arch="arm64" ;;
  *) err "mac-cli ships an Apple Silicon (arm64) build only; detected '$arch'" ;;
esac

command -v curl >/dev/null 2>&1 || err "curl is required"
command -v tar  >/dev/null 2>&1 || err "tar is required"

# Resolve latest version by parsing the redirect from /releases/latest. This
# avoids the 60/hr anonymous GitHub API rate limit. Falls back to the API if
# the redirect doesn't expose a tag (unreleased repo, etc.).
if [ -z "$VERSION" ]; then
  log "resolving latest release"
  final="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" || true)"
  VERSION="$(printf '%s\n' "$final" | sed -nE 's,.*/tag/v?([^/?#]+).*,\1,p')"
  if [ -z "$VERSION" ]; then
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | awk -F'"' '/"tag_name":/ {print $4; exit}' \
      | sed 's/^v//')"
  fi
  [ -n "$VERSION" ] || err "could not determine latest release for $REPO"
fi
VERSION="${VERSION#v}"

TARBALL="mac-cli-v${VERSION}-darwin-${arch}.tar.gz"
URL="https://github.com/$REPO/releases/download/v${VERSION}/${TARBALL}"

if [ -z "$PREFIX" ]; then
  if [ -w /usr/local/bin ] 2>/dev/null; then
    PREFIX="/usr/local/bin"
  else
    PREFIX="$HOME/.local/bin"
  fi
fi

log "downloading $TARBALL"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fL --progress-bar "$URL" -o "$tmp/$TARBALL" \
  || err "download failed: $URL"

log "extracting"
tar -xzf "$tmp/$TARBALL" -C "$tmp"
[ -x "$tmp/mac-cli" ] || err "tarball did not contain a mac-cli binary"

mkdir -p "$PREFIX"
target="$PREFIX/mac-cli"
install -m 0755 "$tmp/mac-cli" "$target"

# Strip the curl-applied quarantine xattr so Gatekeeper doesn't block first run.
xattr -d com.apple.quarantine "$target" 2>/dev/null || true

log "installed $target"
"$target" version

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) log "note: $PREFIX is not on PATH — add 'export PATH=\"$PREFIX:\$PATH\"' to your shell rc" ;;
esac
