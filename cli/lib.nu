# Stop with a plain error message.
export def fail [message: string]: oneof<nothing, record> -> error {
    $in | ignore

    error make {msg: $message}
}

# Print a warning to stderr with a yellow icon.
export def warn [message: string]: nothing -> nothing {
    print --stderr $"(ansi yellow)[W](ansi reset) ($message)"
}

# Run a command body and print a failure with a red icon, without a stack trace.
export def report-error [body: closure]: nothing -> nothing {
    try {
        do $body
    } catch {|err|
        print --stderr $"(ansi red)[E](ansi reset) ($err.msg)"
        exit 1
    }
}

# Remove a file or a directory when it exists, or fail with the reason.
export def remove-path [path: path]: nothing -> nothing {
    try {
        rm --force --recursive $path
    } catch {|err|
        fail $"Cannot remove ($path): ($err.msg)"
    }
}
