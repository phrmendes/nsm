#!/usr/bin/env nu

const ASSETS = [nsm-linux-x86_64 nsm-darwin-arm64 nsm-darwin-x86_64]

if (gh release view $env.TAG | complete).exit_code == 0 {
    print --stderr 'The release already exists.'
    exit 0
}

for asset in $ASSETS {
    nix build $'.#($asset)' --out-link result
    cp --force result $asset
    $'(open --raw $asset | hash sha256)  ($asset)(char nl)' | save --append SHA256SUMS
}

let key = mktemp
$'($env.RELEASE_SIGNING_KEY | str trim)(char nl)' | save --force $key
chmod 600 $key
ssh-keygen -Y sign -f $key -n nsm SHA256SUMS
rm $key

let scripts = $env.CURRENT_FILE | path dirname

with-env {VERSION: ($env.TAG | str replace --regex '^v' '')} {
    nu ($scripts | path join stamp-installer.nu)
}

nu ($scripts | path join get-notes.nu) | save --force notes.md

(
    gh release create $env.TAG
        --verify-tag
        --title $env.TAG
        --notes-file notes.md
        ...$ASSETS
        SHA256SUMS
        SHA256SUMS.sig
        install.sh
)
