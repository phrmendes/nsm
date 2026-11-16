use config.nu [get-config]
use lib.nu [fail remove-path]
use store.nu [get-display-path get-socket resolve-target save-session touch-session]

# Start a detached server for a session, in the directory of the project.
def start-server [name: string, path: path]: nothing -> nothing {
    let socket = (get-socket $name)

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

# Open a session in a kitty tab, or in the current terminal. The tab runs the UI of the server and closes on `:detach`.
def open-session [name: string, path: path, --here]: nothing -> nothing {
    let socket = (get-socket $name)
    let kitty = $env.KITTY_LISTEN_ON?

    touch-session $name

    if ($kitty | is-not-empty) {
        let expression = [
            'setenv("KITTY_LISTEN_ON", '
            ($kitty | to json)
            ')'
        ] | str join

        nvim --clean --server $socket --remote-expr $expression | ignore
    }

    if $here or ($kitty | is-empty) {
        print $'Opening ($name) (get-display-path $path)…'
        nvim --server $socket --remote-ui
        return
    }

    let focus = kitten @ focus-tab --match $'env:NSM_SESSION=($name)' | complete

    if $focus.exit_code != 0 {
        print $'Opening ($name) (get-display-path $path)…'

        let launch = [
            launch
            --type=tab
            --tab-title
            $name
            --cwd
            $path
            --env
            $'NSM_SESSION=($name)'
            nvim
            --server
            $socket
            --remote-ui
        ]

        kitten @ ...$launch | ignore
    }
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
    let result = nvim --clean --server (get-socket $name) --remote-expr $expression | complete

    if $result.exit_code != 0 {
        return false
    }

    ($result.stdout | str trim) != '0'
}

# Create the session when it is missing, start its server when it is stopped, and open it.
export def connect-session [target: oneof<string, nothing>, --here]: nothing -> nothing {
    if $target == null {
        return
    }

    let session = resolve-target $target

    save-session $session.name $session.path

    if not (is-alive (get-socket $session.name)) {
        start-server $session.name $session.path
    }

    open-session $session.name $session.path --here=$here
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
