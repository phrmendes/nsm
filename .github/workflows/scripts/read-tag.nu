#!/usr/bin/env nu

let tag = git tag --points-at HEAD
| lines
| where {|line| $line =~ '^v[0-9]' }
| get --optional 0
| default ''

$'name=($tag)(char nl)' | save --append $env.GITHUB_OUTPUT
