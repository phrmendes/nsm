use config.nu [get-config]
use lib.nu [fail remove-path]
use store.nu [get-display-path get-session resolve-target save-session touch-session]

# Start a detached server for a session, in the directory of the project.
def start-server [name: string, path: path, socket: path]: nothing -> nothing {
    remove-path $socket

    try {
        cd $path
    } catch {|err|
        fail $'Cannot enter ($path): ($err.msg)'
    }

    let restore = get-restore-args $path

    with-env {NSM_SESSION: $name} {
        setsid --fork nvim --headless --listen $socket ...$restore o+e> /dev/null
    }

    if not (wait-until { is-alive $socket }) {
        fail $'The server of ($name) did not start.'
    }
}

# Open a session in the current terminal. The UI closes on `:detach`.
def open-session [name: string, path: path, socket: path]: nothing -> nothing {
    touch-session $name

    print $'Opening ($name) (get-display-path $path)…'
    nvim --server $socket --remote-ui
}

# Check whether a server answers on a socket.
export def is-alive [socket: path]: nothing -> bool {
    if not ($socket | path exists) {
        return false
    }

    (nvim --clean --server $socket --remote-expr 1 | complete).exit_code == 0
}

# Wait until a check passes, for at most five seconds.
export def wait-until [check: closure]: nothing -> bool {
    for _ in 1..50 {
        if (do $check) {
            return true
        }

        sleep 100ms
    }

    false
}

# Return whether a running server has listed buffers with unsaved changes.
export def has-unsaved-changes [name: string]: nothing -> bool {
    let expression = 'len(filter(getbufinfo({"buflisted": 1}), {_, b -> b.changed}))'
    let socket = (get-session $name).socket
    let result = nvim --clean --server $socket --remote-expr $expression | complete

    if $result.exit_code != 0 {
        return false
    }

    ($result.stdout | str trim) != '0'
}

# Create the session when it is missing, and start its server when it is stopped.
export def start-session [target: string]: nothing -> record<name: string, path: string, socket: string> {
    let target_session = resolve-target $target
    let session = save-session $target_session.name $target_session.path

    if not (is-alive $session.socket) {
        start-server $session.name $session.path $session.socket
    }

    $session
}

# Create the session when it is missing, start its server when it is stopped, and open it.
export def connect-session [target: oneof<string, nothing>]: nothing -> nothing {
    if $target == null {
        return
    }

    let session = start-session $target

    open-session $session.name $session.path $session.socket
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
