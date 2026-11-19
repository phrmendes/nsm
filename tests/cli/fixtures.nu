use ../../cli/lib.nu [fail remove-path]
use ../../cli/server.nu [is-alive wait-until]
use ../../cli/store.nu [create-store]

# Return the path of bash, or an `env` command that finds it.
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

# Run a closure in a temporary directory, and remove the directory also on failure.
export def in-root [body: closure]: nothing -> nothing {
    let root = mktemp --directory | path expand

    try {
        do $body $root
    } catch {|err|
        try { remove-path $root }
        print --stderr ($err.rendered? | default $err.msg)
        error make {msg: $err.msg}
    }

    remove-path $root
}

# Run a closure against an empty session store in a temporary directory.
export def in-store [body: closure]: nothing -> nothing {
    in-root {|root|
        with-env {XDG_STATE_HOME: $root, HOME: $root} {
            create-store
            do $body $root
        }
    }
}

# Create an nvim shim that logs its arguments and starts a real server that quits after one minute.
export def make-shim [path: path, --interpreter: string = '/usr/bin/env bash']: nothing -> nothing {
    let nvim = which nvim | where type == external | get --optional 0.path
    let quit = "call timer_start(60000, {-> execute('qall!')})"
    let script = [
        $"#!($interpreter)"
        "printf '%s\\n' \"$*\" >> \"$SHIM_LOG\""
        'previous=""'
        'for argument in "$@"; do'
        $"  if [ \"$previous\" = \"--listen\" ]; then '($nvim)' --clean --headless --listen \"$argument\" -c \"($quit)\" </dev/null >/dev/null 2>&1 & fi"
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

# Run SQL with named parameters against a database file.
export def query-store [db: path, sql: string, --params: record = {}]: nothing -> table {
    try {
        open $db | query db $sql --params $params
    } catch {|err|
        fail $'Cannot query ($db): ($err.msg)'
    }
}

# Return the message of the error that a closure raises, or nothing.
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
    job spawn { nvim --clean --headless --listen $socket ...$files } | ignore

    if not (wait-until { is-alive $socket }) {
        fail $'Cannot start a test server on ($socket).'
    }
}

# Stop a server that a test started, and wait until its socket is gone.
export def stop-server [socket: path]: nothing -> nothing {
    nvim --clean --server $socket --remote-send '<C-\\><C-N>:qall!<CR>' | complete | ignore
    wait-until { not ($socket | path exists) } | ignore
}

# Run a closure, then a cleanup closure also when the first one fails.
export def finally [cleanup: closure, body: closure]: nothing -> nothing {
    try {
        do $body
    } catch {|err|
        do $cleanup
        error make {msg: $err.msg}
    }

    do $cleanup
}

# Create a bin directory with nvim and setsid shims, and return its path.
export def make-shims [root: path]: nothing -> string {
    let bin = $root | path join bin
    make-dir $bin
    make-shim ($bin | path join nvim) --interpreter (get-bash)
    make-setsid-shim ($bin | path join setsid)
    $bin
}

# Return a PATH that puts a directory before the current PATH.
def with-bin [bin: path]: nothing -> string {
    [$bin] | append $env.PATH | str join (char esep)
}

# Run a closure with the shims on PATH and a log file of their calls.
export def with-shim-env [
    root: path
    bin: path
    body: closure
    --log: string = 'calls.log'
]: nothing -> nothing {
    let stop_servers = {||
        glob ($root | path join '**/*.sock') | where {|socket| is-alive $socket } | each {|socket| stop-server $socket } | ignore
    }

    finally $stop_servers {
        with-env {
            XDG_STATE_HOME: $root
            HOME: $root
            PATH: (with-bin $bin)
            SHIM_LOG: ($root | path join $log)
        } {
            do $body
        } | ignore
    }
}

# Point the socket of a stored session at a path.
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
