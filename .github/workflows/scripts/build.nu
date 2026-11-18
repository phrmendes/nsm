#!/usr/bin/env nu

const IMAGE = 'nsm-x86_64.AppImage'

if (gh release view $env.TAG | complete).exit_code == 0 {
    print 'The release already exists.'
    exit 0
}

nix build '.#nsm-appimage'
cp result $IMAGE

$'(open --raw $IMAGE | hash sha256)  ($IMAGE)(char nl)' | save --force $'($IMAGE).sha256'
$'publish=true(char nl)' | save --append $env.GITHUB_OUTPUT
