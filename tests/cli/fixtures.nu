use ../../cli/lib.nu [fail remove-path]
use ../../cli/server.nu [is-alive wait-until]
use ../../cli/store.nu [create-store]

# Return the path of a bash that is on PATH.
export def get-bash []: nothing -> string {
    which bash | get --optional 0.path | default '/usr/bin/env bash'
}

# Create a directory, or fail with the reason.
export def make-dir [path: path]: nothing -> nothing {
    try {
        mkdir $path
    } catch {|err|
        fail $"Cannot create ($path): ($err.msg)"
    }
}

# Run the body in a temporary directory and remove the directory, also on failure.
export def in-root [body: closure]: nothing -> nothing {
    let root = mktemp --directory

    try {
        do $body $root
    } catch {|err|
        remove-path $root
        print --stderr ($err.rendered? | default $err.msg)
        error make {msg: $err.msg}
    }

    remove-path $root
}

# Run the body against an isolated, empty session store, and remove the store.
export def in-store [body: closure]: nothing -> nothing {
    in-root {|root|
        with-env {XDG_STATE_HOME: $root, HOME: $root} {
            create-store
            do $body $root
        }
    }
}

# Create a bash shim that logs its arguments and creates a file after `--listen`.
export def make-shim [path: path, --interpreter: string = '/usr/bin/env bash']: nothing -> nothing {
    let script = [
        $"#!($interpreter)"
        "printf '%s\\n' \"$*\" >> \"$SHIM_LOG\""
        'previous=""'
        'for argument in "$@"; do'
        '  if [ "$previous" = "--listen" ]; then : > "$argument"; fi'
        '  previous="$argument"'
        'done'
        'exit 0'
    ] | str join (char nl)

    write-text $path $script
    chmod +x $path
}

# Create a setsid shim that drops the session flags and runs the child in this process.
export def make-setsid-shim [path: path]: nothing -> nothing {
    let bash = get-bash
    write-text $path ([$"#!($bash)" 'shift' 'exec "$@"'] | str join (char nl))
    chmod +x $path
}

# Create an fzf shim. It logs its arguments, saves the input, and prints row `FZF_PICK`.
export def make-fzf-shim [path: path]: nothing -> nothing {
    let bash = get-bash
    let script = [
        $"#!($bash)"
        "printf '%s\\n' \"$*\" > \"$FZF_LOG\""
        'cat > "$FZF_INPUT"'
        'if [ -n "$FZF_CODE" ]; then exit "$FZF_CODE"; fi'
        'sed -n "${FZF_PICK:-1}p" "$FZF_INPUT"'
    ] | str join (char nl)

    write-text $path $script
    chmod +x $path
}

# Create an empty file, or fail with the reason.
export def make-file [path: path]: nothing -> nothing {
    try {
        '' | save --force $path
    } catch {|err|
        fail $"Cannot create ($path): ($err.msg)"
    }
}

# Read a text file, or fail with the reason.
export def read-file [path: path]: nothing -> string {
    try {
        open --raw $path
    } catch {|err|
        fail $"Cannot read ($path): ($err.msg)"
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

# Start a real headless server on the socket and wait until it answers.
export def spawn-server [socket: path, ...files: path]: nothing -> nothing {
    job spawn { nvim --headless --listen $socket ...$files } | ignore

    if not (wait-until { is-alive $socket }) {
        fail $'Cannot start a test server on ($socket).'
    }
}

# Stop a server that a test started.
export def stop-server [socket: path]: nothing -> nothing {
    nvim --clean --server $socket --remote-send '<C-\\><C-N>:qall!<CR>' | complete | ignore
}

# Run a cleanup after the body, also when the body fails.
export def finally [cleanup: closure, body: closure]: nothing -> nothing {
    try {
        do $body
    } catch {|err|
        do $cleanup
        error make {msg: $err.msg}
    }

    do $cleanup
}

# Create a bin directory with nvim, setsid, and fzf shims, and return its path.
export def make-shims [root: path]: nothing -> string {
    let bin = $root | path join bin
    make-dir $bin
    make-shim ($bin | path join nvim) --interpreter (get-bash)
    make-setsid-shim ($bin | path join setsid)
    make-fzf-shim ($bin | path join fzf)
    $bin
}

# Return a PATH that keeps the current one and puts the bin shims first.
def with-bin [bin: path]: nothing -> string {
    [$bin] | append $env.PATH | str join (char esep)
}

# Run the body with the shims on PATH and a log of their calls.
export def with-shim-env [
    root: path
    bin: path
    body: closure
    --log: string = 'calls.log'
]: nothing -> nothing {
    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: (with-bin $bin)
        SHIM_LOG: ($root | path join $log)
    } {
        do $body
    } | ignore
}

# Point the socket of a session at a given path.
export def set-socket [root: path, name: string, socket: path]: nothing -> nothing {
    query-store ($root | path join nsm sessions.db) 'update sessions set socket = :socket where name = :name' --params {name: $name, socket: $socket} | ignore
}

# Run the `test *` commands of a test file, each in its own process.
export def run-tests [file: path]: nothing -> nothing {
    print '🧪 Running tests...'

    let script = (
        [
            ('let file_path = ' + ($file | to nuon))
            ('source ' + ($file | to nuon))
            'let cmds = (scope commands | where {|command| ($command.type == "custom") and ($command.name | str starts-with "test ") and not ($command.description | str starts-with "ignore") } | get name)'
            'for test in $cmds {'
            '  print $"\u{1F539} ($test)"'
            '  nu --no-config-file --commands $"source ($file_path); ($test)"'
            '}'
        ]
        | str join (char nl)
    )

    nu --no-config-file --commands $script

    print '✅ Tests completed successfully'
}

# Parse JSON text, or fail with the reason.
export def from-json []: string -> table {
    try {
        from json
    } catch {|err|
        fail $"Cannot parse JSON: ($err.msg)"
    }
}
