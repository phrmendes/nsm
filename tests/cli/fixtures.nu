use ../../cli/lib.nu [fail remove-path]
use ../../cli/store.nu [create-store]

# Create a directory, or fail with the reason.
export def make-dir [path: path]: nothing -> nothing {
    try {
        mkdir $path
    } catch {|err|
        fail $"Cannot create ($path): ($err.msg)"
    }
}

# Create an isolated session store, run the test body, and remove the store.
export def in-store [body: closure]: nothing -> nothing {
    let root = mktemp --directory

    with-env {XDG_STATE_HOME: $root, HOME: $root} {
        create-store
        do $body $root
    }

    remove-path $root
}

# Write an executable bash shim that logs its arguments and exits with a configurable code.
export def make-shim [path: path, --interpreter: string = '/usr/bin/env bash']: nothing -> nothing {
    let script = [
        $"#!($interpreter)"
        'printf \'%s\\n\' "$*" >> "$SHIM_LOG"'
        'exit 0'
    ] | str join (char nl)

    try {
        $script | save --force $path
        chmod +x $path
    } catch {|err|
        fail $"Cannot create ($path): ($err.msg)"
    }
}

# Create an empty file, or fail with the reason.
export def make-file [path: path]: nothing -> nothing {
    try {
        '' | save --force $path
    } catch {|err|
        fail $"Cannot create ($path): ($err.msg)"
    }
}

# Write a text file, or fail with the reason.
export def write-text [path: path, text: string]: nothing -> nothing {
    try {
        $text | save --force $path
    } catch {|err|
        fail $"Cannot write ($path): ($err.msg)"
    }
}

# Run SQL against a database file with bound parameters.
export def query-store [db: path, sql: string, --params: record = {}]: nothing -> table {
    try {
        open $db | query db $sql --params $params
    } catch {|err|
        fail $'Cannot query ($db): ($err.msg)'
    }
}

# Return the message of an error, or null when the closure succeeds.
export def error-message [body: closure]: nothing -> oneof<string, nothing> {
    try {
        do $body | ignore
        null
    } catch {|err|
        $err.msg
    }
}
