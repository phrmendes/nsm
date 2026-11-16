#!/bin/sh
# Install the nsm command from a GitHub release.
#
# Environment:
#   NSM_VERSION      Release version to install, without the leading "v" (default: latest)
#   NSM_BASE_URL     Download base URL (default: the GitHub release of that version)
#   NSM_INSTALL_DIR  Install directory (default: ~/.local/bin)

set -eu

ASSET=nsm-x86_64.AppImage
VERSION=${NSM_VERSION:-latest}
INSTALL_DIR=${NSM_INSTALL_DIR:-$HOME/.local/bin}
BASE_URL=${NSM_BASE_URL:-}

fail() {
    printf 'nsm: %s\n' "$1" >&2
    exit 1
}

note() {
    printf 'nsm: %s\n' "$1" >&2
}

download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1"
    else
        fail 'Install curl or wget first.'
    fi
}

[ "$(uname -s)" = Linux ] || fail 'nsm runs on Linux only.'
[ "$(uname -m)" = x86_64 ] || fail 'nsm needs an x86_64 machine.'

if [ "$BASE_URL" = "" ]; then
    BASE_URL="https://github.com/phrmendes/nsm/releases"
    if [ "$VERSION" = latest ]; then
        BASE_URL="$BASE_URL/latest/download"
    else
        BASE_URL="$BASE_URL/download/v${VERSION#v}"
    fi
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

printf 'nsm: downloading %s\n' "$BASE_URL/$ASSET"
download "$BASE_URL/$ASSET" "$temporary/$ASSET"
download "$BASE_URL/$ASSET.sha256" "$temporary/$ASSET.sha256"

command -v sha256sum >/dev/null 2>&1 || fail 'Install coreutils for sha256sum.'

if ! (cd "$temporary" && sha256sum -c "$ASSET.sha256" >/dev/null); then
    fail 'The checksum does not match. The download is broken, or someone replaced it.'
fi

mkdir -p "$INSTALL_DIR"
install -m 755 "$temporary/$ASSET" "$INSTALL_DIR/nsm"
printf 'nsm: installed %s\n' "$INSTALL_DIR/nsm"

case ":$PATH:" in
*":$INSTALL_DIR:"*) ;;
*) note "$INSTALL_DIR is not on PATH. Add it to your shell profile." ;;
esac

command -v nvim >/dev/null 2>&1 || note 'Neovim is not on PATH. Install Neovim 0.12 or newer.'

command -v git >/dev/null 2>&1 || note 'git is not on PATH. Sessions take the directory name, not the repository name.'

if [ ! -e /dev/fuse ]; then
    note 'There is no /dev/fuse. Run nsm with APPIMAGE_EXTRACT_AND_RUN=1, which is slower.'
fi
