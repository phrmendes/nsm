use config.nu [get-config]
use lib.nu [EXIT_UNSAVED fail get-display-path remove-path]
use store.nu [delete-session get-session save-session touch-session]
use target.nu [resolve-target]

const POLL_ATTEMPTS = 500
const POLL_INTERVAL = 10ms
const REMOTE_TIMEOUT = 2
const SIGNAL_ATTEMPTS = 100

# Close every file above 2 before `nvim` runs, so the server does not hold the AppImage mount.
const CLOSE_FDS = 'for fd in /proc/self/fd/*; do fd=${fd##*/}; [ "$fd" -gt 2 ] && eval "exec $fd>&-"; done; exec "$@"'

# Start a detached server for a session in its directory, and wait until it listens.
def start-server [session: record<name: string, path: string, socket: string>]: nothing -> nothing {
    remove-path $session.socket

    try {
        cd $session.path
    } catch {|err|
        fail $'Cannot enter ($session.path): ($err.msg)'
    }

    let restore = get-restore-args $session.path

    print --stderr $'Starting ($session.name)…'

    with-env {NSM_SESSION: $session.name} {
        setsid --fork bash -c $CLOSE_FDS bash nvim --headless --listen $session.socket ...$restore o+e> /dev/null
    }

    if not (wait-until { is-alive $session.socket }) {
        fail $'The server of ($session.name) did not start.'
    }
}

# Run a remote expression on a server, and return the completed command.
def remote-expr [socket: path, expression: string]: nothing -> record<stdout: string, stderr: string, exit_code: int> {
    timeout $REMOTE_TIMEOUT nvim --clean --server $socket --remote-expr $expression | complete
}

# Open a session in the current terminal.
def open-session [session: record<name: string, path: string, socket: string>]: nothing -> nothing {
    touch-session $session.name

    print $'Opening ($session.name) (get-display-path $session.path)…'
    nvim --server $session.socket --remote-ui
}

# Check whether a process runs. A zombie waits for its parent and does not run.
def is-running [pid: int]: nothing -> bool {
    try {
        (
            open --raw $'/proc/($pid)/stat'
            | parse --regex '\) (?<state>\S)'
            | get state.0
        ) != 'Z'
    } catch {
        false
    }
}

# Send a signal to a server, and wait until its process ends.
def signal-server [pid: int, signal: string]: nothing -> bool {
    ^kill -s $signal $pid | complete | ignore

    wait-until --attempts $SIGNAL_ATTEMPTS { not (is-running $pid) }
}

# Ask a server to quit, and end it with a signal when `force` is set.
def stop-server [name: string, socket: path, force: bool]: nothing -> nothing {
    timeout $REMOTE_TIMEOUT nvim --clean --server $socket --remote-send '<C-\><C-N>:qall!<CR>' | complete | ignore

    let attempts = if $force { $SIGNAL_ATTEMPTS } else { $POLL_ATTEMPTS }

    if (wait-until --attempts $attempts { not ($socket | path exists) }) {
        return
    }

    let pid = if $force { find-server-pid $socket } else { null }
    let ended = $pid != null and ((signal-server $pid TERM) or (signal-server $pid KILL))

    if not $ended {
        let reason = if $force and $pid == null { ', and its process is unknown' } else { '' }

        fail $'The server of ($name) did not stop($reason).'
    }
}

# Check whether a server listens on a socket.
export def is-alive [socket: path]: nothing -> bool {
    open --raw /proc/net/unix | str contains $' ($socket)(char nl)'
}

# Poll a condition every 10 ms, and return whether it passed before the attempts ran out.
export def wait-until [check: closure, --attempts: int = $POLL_ATTEMPTS]: nothing -> bool {
    for _ in 1..$attempts {
        if (do $check) {
            return true
        }

        sleep $POLL_INTERVAL
    }

    false
}

# Check whether a server has listed buffers with unsaved changes.
export def has-unsaved-changes [name: string]: nothing -> bool {
    let expression = 'len(filter(getbufinfo({"buflisted": 1}), {_, b -> b.changed}))'
    let socket = (get-session $name).socket
    let result = remote-expr $socket $expression
    let count = $result.stdout | str trim

    if $result.exit_code == 124 {
        fail $'The server of ($name) does not answer. Run `nsm kill --force ($name)`.' --code $EXIT_UNSAVED
    }

    if $result.exit_code != 0 {
        fail $'Cannot query the server of ($name): ($result.stderr | str trim)'
    }

    if $count !~ '^[0-9]+$' {
        fail $'Cannot query the server of ($name): it answered "($count)".'
    }

    $count != '0'
}

# Return the names of the running sessions that have unsaved changes.
export def get-dirty-sessions [sessions: table<name: string, socket: string>]: nothing -> list<string> {
    $sessions
    | par-each --keep-order {|session|
        {name: $session.name, dirty: ((is-alive $session.socket) and (has-unsaved-changes $session.name))}
    }
    | where dirty
    | get name
}

# Return the process id of the server that listens on a socket, or nothing.
export def find-server-pid [socket: path]: nothing -> oneof<int, nothing> {
    let pids = glob '/proc/[0-9]*/cmdline'
    | where {|file|
        let arguments = try { open --raw $file | split row (char --integer 0) } catch { [] }
        let index = $arguments | enumerate | where item == '--listen' | get --optional 0.index

        $index != null and ($arguments | get --optional ($index + 1)) == $socket
    }
    | each {|file| $file | path dirname | path basename | into int }

    $pids | get --optional 0
}

# Stop the server of a session, and forget the session.
export def stop-session [name: string, --force]: nothing -> nothing {
    let session = get-session $name

    if ($session.socket | path exists) {
        stop-server $name $session.socket $force
    }

    remove-path $session.socket
    delete-session $name

    print $'Stopped ($name).'
}

# Create the session when it is missing, and start its server when it does not run.
export def start-session [target: string]: nothing -> record<name: string, path: string, socket: string> {
    let target_session = resolve-target $target
    let session = save-session $target_session.name $target_session.path

    if not (is-alive $session.socket) {
        start-server $session
    }

    $session
}

# Create the session when it is missing, start its server when it does not run, and open it.
export def connect-session [target: oneof<string, nothing>]: nothing -> nothing {
    if $target == null {
        return
    }

    let session = start-session $target

    open-session $session
}

# Return the arguments that restore a session file, when one is configured and exists.
export def get-restore-args [path: path]: nothing -> list<string> {
    let file = (get-config).restore.file

    if ($file | is-empty) {
        return []
    }

    let target = if ($file | str starts-with '/') {
        $file
    } else {
        $path | path join $file
    }

    if not ($target | path exists) {
        return []
    }

    ['-S' $target]
}
