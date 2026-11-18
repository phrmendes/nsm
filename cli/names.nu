use lib.nu [fail]

const NAME_CHARS = 'a-zA-Z0-9._-'

# Fail when a session name is empty or has an unsafe character.
export def check-name [name: string]: nothing -> nothing {
    if $name !~ $'^[($NAME_CHARS)]+$' {
        fail 'A session name may only hold letters, digits, dots, dashes and underscores.'
    }
}

# Return the basename of the git root of a directory, or of the directory itself.
export def get-session-name [directory: path]: nothing -> string {
    let root = if (which git | is-empty) {
        null
    } else {
        git -C $directory rev-parse --show-toplevel | complete
    }

    let base = if $root == null or $root.exit_code != 0 {
        $directory
    } else {
        $root.stdout | str trim
    }

    $base | path basename | str replace --all --regex $'[^($NAME_CHARS)]' '-'
}

# Return the first of a base name and its numbered variants that no session uses.
@example 'a free name stays as it is' { get-free-name app } --result app
@example 'a taken name gets a number' { get-free-name app app app-2 } --result app-3
export def get-free-name [base: string, ...taken: string]: nothing -> string {
    mut candidate = $base
    mut suffix = 1

    while $candidate in $taken {
        $suffix += 1
        $candidate = $'($base)-($suffix)'
    }

    $candidate
}
