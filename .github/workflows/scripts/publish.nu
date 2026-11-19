#!/usr/bin/env nu

const IMAGE = 'nsm-x86_64.AppImage'

if (gh release view $env.TAG | complete).exit_code == 0 {
    print 'The release already exists.'
    exit 0
}

nix build '.#nsm-appimage'
cp result $IMAGE

$'(open --raw $IMAGE | hash sha256)  ($IMAGE)(char nl)' | save --force $'($IMAGE).sha256'

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
        $IMAGE
        $'($IMAGE).sha256'
        install.sh
)
