#!/usr/bin/env nu

const ASSETS = [nsm-linux-x86_64 nsm-darwin-arm64 nsm-darwin-x86_64]

if (gh release view $env.TAG | complete).exit_code == 0 {
    print --stderr 'The release already exists.'
    exit 0
}

for asset in $ASSETS {
    nix build $'.#($asset)' --out-link result
    cp --force result $asset
    $'(open --raw $asset | hash sha256)  ($asset)(char nl)' | save --force $'($asset).sha256'
}

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
        ...($ASSETS | each {|asset| $'($asset).sha256' })
        install.sh
)
