#!/usr/bin/env nu

let line = $'VERSION=($env.VERSION)'

open --raw scripts/install.sh
| str replace --regex '(?m)^VERSION=latest$' $line
| save --force install.sh

let stamped = open --raw install.sh | lines | where {|text| $text == $line } | is-not-empty

if not $stamped {
    error make {msg: 'The installer does not carry the version.'}
}
