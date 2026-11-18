#!/usr/bin/env nu

const IMAGE = 'nsm-x86_64.AppImage'

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
