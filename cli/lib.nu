# Exit code of a command that refused a change because of unsaved buffers.
export const EXIT_UNSAVED = 3

# Stop with a plain error message, and the exit code that the CLI reports.
export def fail [message: string, --code(-c): int = 1]: oneof<nothing, record> -> error {
    $in | ignore

    error make {
        msg: $message
        code: $"nsm::exit::($code)"
    }
}

def get-exit-code [err: record]: nothing -> int {
    let code = $err | get --optional details.code

    if $code == null or not ($code =~ '^nsm::exit::[0-9]+$') {
        return 1
    }

    $code | str replace 'nsm::exit::' '' | into int
}

export def warn [message: string]: nothing -> nothing {
    print --stderr $"(ansi yellow)[W](ansi reset) ($message)"
}

# Run a command body and print a failure with a red icon, without a stack trace.
export def report-error [body: closure]: nothing -> nothing {
    try {
        do $body
    } catch {|err|
        print --stderr $"(ansi red)[E](ansi reset) ($err.msg)"
        exit (get-exit-code $err)
    }
}

export def remove-path [path: path]: nothing -> nothing {
    try {
        rm --force --recursive $path
    } catch {|err|
        fail $"Cannot remove ($path): ($err.msg)"
    }
}

# Return a path with the home directory written as a tilde.
@example 'a tilde replaces the home' { with-env {HOME: /h} { get-display-path /h/code } } --result '~/code'
export def get-display-path [path: string]: nothing -> string {
    let home = $env.HOME | str trim --right --char '/'

    if $path == $home {
        return '~'
    }

    if ($path | str starts-with $"($home)/") {
        return $"~($path | str substring ($home | str length)..)"
    }

    $path
}

# Return a path relative to a configured project root, or the display path.
@example 'a path under a root loses the root' { get-project-path /p/neovim/nsm [/p] } --result neovim/nsm
export def get-project-path [path: string, ...roots: list<string>]: nothing -> string {
    let target = $path | path expand
    let matches = $roots
    | flatten
    | each {|root| $root | path expand }
    | where {|root| ($target | str starts-with $"($root)/") }
    | sort-by {|root| $root | str length }
    | reverse

    if ($matches | is-empty) {
        return (get-display-path $path)
    }

    $target | str substring (($matches | first | str length) + 1)..
}
