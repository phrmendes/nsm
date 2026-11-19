use config.nu [get-config]
use lib.nu [EXIT_UNSAVED fail get-display-path remove-path]
use store.nu [delete-session get-session save-session touch-session]
use target.nu [resolve-target]

const POLL_ATTEMPTS = 500
const POLL_INTERVAL = 10ms
const REMOTE_TIMEOUT = 2
const SIGNAL_ATTEMPTS = 100
const PLAIN_TIMEOUT = 5
const ENVIRONMENT_INTERVAL = 200ms
const HEARTBEAT = 5sec

# Write the process id to the file in $1, then close every file above 2 before `nvim` runs, so the server does not hold a file of its parent.
const CLOSE_FDS = 'printf %s $$ > "$1"; shift; for fd in /dev/fd/*; do fd=${fd##*/}; [ "$fd" -gt 2 ] && eval "exec $fd>&-"; done; exec "$@"'

# Check whether the system is macOS.
def is-macos []: nothing -> bool {
    $nu.os-info.name == 'macos'
}

# Return the file that holds the process id of the launcher of a server.
def get-pid-file [socket: path]: nothing -> string {
    $socket | str replace --regex '\.sock$' '.pid'
}

# Check whether the launcher of a server still runs, or a process listens on its socket path.
def is-starting [socket: path]: nothing -> bool {
    let launched = try {
        is-running (open --raw (get-pid-file $socket) | str trim | into int)
    } catch {
        false
    }

    $launched or ((find-server-pid $socket) != null)
}

# Return the log file that sits next to the socket of a server.
def get-log-file [socket: path]: nothing -> string {
    $socket | str replace --regex '\.sock$' '.log'
}

# Return the last lines of a log file without colour codes.
def read-log-tail [log: path]: nothing -> string {
    try {
        open --raw $log | ansi strip | lines | where {|line| $line | is-not-empty } | last 10 | str join (char nl)
    } catch {
        ''
    }
}

# Wait until a server listens or no process starts it, and report an environment load every few seconds.
def wait-for-server [
    session: record<name: string, path: string, socket: string>
    attempts: int
    interval: duration
    report: bool
]: nothing -> nothing {
    let started = date now
    mut next_report = $HEARTBEAT

    for _ in 1..$attempts {
        if (is-alive $session.socket) or not (is-starting $session.socket) {
            return
        }

        sleep $interval

        let elapsed = (date now) - $started

        if $report and $elapsed >= $next_report {
            print --stderr $'Still loading the environment of ($session.name)… ($elapsed / 1sec | math floor) s'
            $next_report += $HEARTBEAT
        }
    }
}

# Start a detached server for a session in its directory, and wait until it listens.
def start-server [session: record<name: string, path: string, socket: string>]: nothing -> nothing {
    let pid_file = get-pid-file $session.socket

    remove-path $session.socket
    remove-path $pid_file

    try {
        cd $session.path
    } catch {|err|
        fail $'Cannot enter ($session.path): ($err.msg)'
    }

    let restore = get-restore-args $session.path
    let environment = get-environment-command $session.path
    let log = get-log-file $session.socket
    let timeout_seconds = if ($environment | is-empty) { $PLAIN_TIMEOUT } else { (get-config).start.timeout }

    print --stderr $'Starting ($session.name)…'

    if ($environment | is-not-empty) {
        print --stderr $'Loading the environment of ($session.name) with ($environment | first)…'
    }

    with-env {NSM_SESSION: $session.name} {
        setsid --fork bash -c $CLOSE_FDS bash $pid_file ...$environment nvim --headless --listen $session.socket ...$restore o+e> $log
    }

    wait-until {
        $pid_file | path exists
    } | ignore

    let interval = if ($environment | is-empty) { $POLL_INTERVAL } else { $ENVIRONMENT_INTERVAL }
    let attempts = ($timeout_seconds * 1sec / $interval) | into int

    (wait-for-server
        $session
        $attempts
        $interval
        ($environment | is-not-empty)
    )

    let failure = if (is-alive $session.socket) {
        null
    } else if (is-starting $session.socket) {
        $'The server of ($session.name) did not start within ($timeout_seconds) s.'
    } else if ($environment | is-empty) {
        $'The server of ($session.name) did not start:(char nl)(read-log-tail $log)'
    } else {
        $'The environment of ($session.name) did not load:(char nl)(read-log-tail $log)'
    }

    if $failure != null {
        fail $failure
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
    if (is-macos) {
        let result = ^ps -o stat= -p $pid | complete
        let state = $result.stdout | str trim

        return (
            $result.exit_code == 0 and ($state | is-not-empty) and not ($state | str starts-with 'Z')
        )
    }

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

# Return the command that loads the environment of a project, or an empty list.
export def get-environment-command [path: path]: nothing -> list<string> {
    if not (get-config).start.environment {
        return []
    }

    let loader = if ($path | path join .envrc | path exists) {
        {
            tool: direnv
            file: .envrc
            command: [direnv exec $path]
        }
    } else if ($path | path join devenv.nix | path exists) {
        {
            tool: devenv
            file: devenv.nix
            command: [devenv shell --]
        }
    } else {
        null
    }

    if $loader == null {
        return []
    }

    if (which $loader.tool | is-empty) {
        fail $'The project has a ($loader.file), but ($loader.tool) is not on PATH.'
    }

    $loader.command
}

# Check whether a process accepts connections on a Unix socket.
export def can-connect [socket: path]: nothing -> bool {
    let probe = 'socket(my $s, PF_UNIX, SOCK_STREAM, 0) or exit 1; connect($s, sockaddr_un($ARGV[0])) or exit 1'

    (^perl -MSocket -e $probe $socket | complete).exit_code == 0
}

# Check whether a server listens on a socket.
export def is-alive [socket: path]: nothing -> bool {
    if (is-macos) {
        return (can-connect $socket)
    }

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

# Return the process id of the line of `ps` text that has the socket as its `--listen` argument, or nothing.
export def find-pid-in-ps [text: string, socket: path]: nothing -> oneof<int, nothing> {
    let needle = $' --listen ($socket) '

    $text
    | lines
    | where {|line| $'($line) ' | str contains $needle }
    | each {|line| $line | str trim | split row ' ' | first | into int }
    | get --optional 0
}

# Return the process id of the server that listens on a socket, or nothing.
export def find-server-pid [socket: path]: nothing -> oneof<int, nothing> {
    if (is-macos) {
        return (find-pid-in-ps (^ps -axww -o pid=,args= | complete | get stdout) $socket)
    }

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
    remove-path (get-log-file $session.socket)
    remove-path (get-pid-file $session.socket)
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
