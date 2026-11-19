#!/usr/bin/env nu

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'

let bump = nix run --inputs-from . nixpkgs#commitizen -- bump --yes | complete

if $bump.exit_code == 21 {
    $'name=(char nl)' | save --append $env.GITHUB_OUTPUT
    exit 0
}

if $bump.exit_code != 0 {
    error make {msg: $bump.stderr}
}

let tag = git describe --tags --abbrev=0

git push origin HEAD $tag

$'name=($tag)(char nl)' | save --append $env.GITHUB_OUTPUT
