#!/bin/sh
# Install the nsm command from a GitHub release. It supports Linux x86_64 and macOS.
#
# Environment:
#   NSM_BASE_URL     Download base URL (default: the GitHub release of that version)
#   NSM_INSTALL_DIR  Install directory (default: ~/.local/bin)
#   NSM_SIGNER       A signer public key for tests. It works only with a file:// base URL.

set -eu

VERSION=latest
SIGNER='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIARc4eYnYQ/xXijIu+I5HkDEJEQQ5zHWYhOKC64ZIXJs'
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
        curl -fsSL "$1" -o "$2" || fail "Cannot download $1."
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$2" "$1" || fail "Cannot download $1."
    else
        fail 'Install curl or wget first.'
    fi
}

system=$(uname -s)
machine=$(uname -m)

case "$system-$machine" in
Linux-x86_64) ASSET=nsm-linux-x86_64 ;;
Darwin-arm64) ASSET=nsm-darwin-arm64 ;;
Darwin-x86_64) ASSET=nsm-darwin-x86_64 ;;
*) fail "nsm does not support $system on $machine." ;;
esac

if [ "$BASE_URL" = "" ]; then
    BASE_URL="https://github.com/phrmendes/nsm/releases"
    if [ "$VERSION" = latest ]; then
        BASE_URL="$BASE_URL/latest/download"
    else
        BASE_URL="$BASE_URL/download/v$VERSION"
    fi
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

case "$BASE_URL" in
file://*) SIGNER=${NSM_SIGNER:-$SIGNER} ;;
esac

printf 'nsm: downloading %s\n' "$BASE_URL/$ASSET"
download "$BASE_URL/$ASSET" "$temporary/$ASSET"
download "$BASE_URL/SHA256SUMS" "$temporary/SHA256SUMS"

if command -v ssh-keygen >/dev/null 2>&1; then
    download "$BASE_URL/SHA256SUMS.sig" "$temporary/SHA256SUMS.sig"
    printf 'nsm-release %s\n' "$SIGNER" >"$temporary/signers"

    ssh-keygen -Y verify -f "$temporary/signers" -I nsm-release -n nsm -s "$temporary/SHA256SUMS.sig" \
        <"$temporary/SHA256SUMS" >/dev/null 2>&1 ||
        fail 'The signature of the release does not match. Someone may have replaced the files.'
else
    note 'ssh-keygen is not on PATH. The signature of the release was not checked.'
fi

if command -v sha256sum >/dev/null 2>&1; then
    check="sha256sum -c"
else
    check="shasum -a 256 -c"
fi

grep " $ASSET\$" "$temporary/SHA256SUMS" >"$temporary/$ASSET.sha256" || fail "SHA256SUMS has no line for $ASSET."

if ! (cd "$temporary" && $check "$ASSET.sha256" >/dev/null 2>&1); then
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

