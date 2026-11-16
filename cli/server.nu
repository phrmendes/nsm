use config.nu [get-config]
use lib.nu [fail get-display-path remove-path]
use store.nu [delete-session get-session save-session touch-session]
use target.nu [resolve-target]

const POLL_ATTEMPTS = 50
const POLL_INTERVAL = 100ms
const REMOTE_TIMEOUT = 2
const PROBE_TIMEOUT = 1

# Start a detached server for a session, in the directory of the project.
def start-server [session: record]: nothing -> nothing {
    remove-path $session.socket

    try {
        cd $session.path
    } catch {|err|
        fail $'Cannot enter ($session.path): ($err.msg)'
    }

    let restore = get-restore-args $session.path

    with-env {NSM_SESSION: $session.name} {
        setsid --fork nvim --headless --listen $session.socket ...$restore o+e> /dev/null
    }

    if not (wait-until { is-alive $session.socket }) {
        fail $'The server of ($session.name) did not start.'
    }
}

# Run a remote expression on a server and return the completed command.
# A server that does not answer in time counts as unreachable.
def remote-expr [socket: path, expression: string, --timeout: int = $REMOTE_TIMEOUT]: nothing -> record {
    timeout $timeout nvim --clean --server $socket --remote-expr $expression | complete
}

# Open a session in the current terminal. The UI closes on `:detach`.
def open-session [session: record]: nothing -> nothing {
    touch-session $session.name

    print $'Opening ($session.name) (get-display-path $session.path)…'
    nvim --server $session.socket --remote-ui
}

# Return the state of a server: `stopped` when it does not answer, `busy` when it answers
# too late, and `running` when it answers in time.
export def get-state [socket: path]: nothing -> string {
    if not ($socket | path exists) {
        return 'stopped'
    }

    let result = remote-expr $socket '1' --timeout $PROBE_TIMEOUT

    if $result.exit_code == 0 {
        return 'running'
    }

    if $result.exit_code == 124 {
        return 'busy'
    }

    'stopped'
}

# Check whether a server answers on a socket. A busy server counts as alive.
export def is-alive [socket: path]: nothing -> bool {
    (get-state $socket) != 'stopped'
}

# Wait until a check passes, for at most five seconds.
export def wait-until [check: closure]: nothing -> bool {
    for _ in 1..$POLL_ATTEMPTS {
        if (do $check) {
            return true
        }

        sleep $POLL_INTERVAL
    }

    false
}

# Return whether a running server has listed buffers with unsaved changes.
export def has-unsaved-changes [name: string]: nothing -> bool {
    let expression = 'len(filter(getbufinfo({"buflisted": 1}), {_, b -> b.changed}))'
    let socket = (get-session $name).socket
    let result = remote-expr $socket $expression

    if $result.exit_code != 0 {
        fail $'Cannot query the server of ($name): ($result.stderr | str trim)'
    }

    ($result.stdout | str trim) != '0'
}

# Return the names of the live sessions that have unsaved changes.
export def get-dirty-sessions [sessions: table]: nothing -> list<string> {
    $sessions
    | where {|session| is-alive $session.socket }
    | where {|session| has-unsaved-changes $session.name }
    | get name
}

# Stop the server of a session and forget it.
export def stop-session [name: string]: nothing -> nothing {
    let session = get-session $name

    if (is-alive $session.socket) {
        nvim --clean --server $session.socket --remote-send '<C-\><C-N>:qall!<CR>'

        if not (wait-until { not (is-alive $session.socket) }) {
            fail $'The server of ($name) did not stop.'
        }
    }

    remove-path $session.socket
    delete-session $name

    print $'Stopped ($name).'
}

# Create the session when it is missing, and start its server when it is stopped.
export def start-session [target: string]: nothing -> record<name: string, path: string, socket: string> {
    let target_session = resolve-target $target
    let session = save-session $target_session.name $target_session.path

    if not (is-alive $session.socket) {
        start-server $session
    }

    $session
}

# Create the session when it is missing, start its server when it is stopped, and open it.
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
