use lib.nu [fail remove-path]
use picker.nu [pick-candidate]
use render.nu [format-sessions]
use server.nu [connect-session has-unsaved-changes is-alive wait-until]
use store.nu [
    check-name
    create-store
    delete-session
    get-previous-session-name
    get-session
    get-socket
    list-sessions
    save-session
]

# Pick another session and open it. The picker does not list the current session.
def "main switch" [
    --scope: string = '' # Only pick sessions under this directory
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store

    let current = $env.NSM_SESSION?
    let chosen = if $current == null {
        pick-candidate --scope $scope
    } else {
        pick-candidate --exclude $current --scope $scope
    }

    connect-session $chosen --here=$here
}

# Return to the session that you opened before the current one.
def "main last" [
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store

    let previous = get-previous-session-name

    if $previous == null {
        fail 'There is no previous session.'
    }

    connect-session $previous --here=$here
}

# Create or attach to a session. The target is a session name or a directory. Without a target, pick one.
def "main attach" [
    target?: string # A session name or a directory
    --scope: string = '' # Only pick sessions under this directory
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store

    connect-session ($target | default {|| pick-candidate --scope $scope }) --here=$here
}

# Create a session with a name of your choice for a directory, and open it.
def "main new" [
    name: string # The name of the session
    path?: path # The directory of the project, the current directory by default
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store
    check-name $name

    let directory = $path | default $env.PWD | path expand

    if ($directory | path type) != 'dir' {
        fail $'($directory) is not a directory.' $path --text directory
    }

    if (is-alive (get-socket $name)) {
        fail $'The session ($name) is already running.' $name --text session
    }

    save-session $name $directory
    connect-session $name --here=$here
}

# Print a compact table of sessions or a clear empty-state message.
def "main list" []: nothing -> nothing {
    create-store

    let sessions = list-sessions
    | insert running {|session| is-alive $session.socket }

    print (format-sessions $sessions)
}

# Stop the server of a session and forget it.
def stop-session [name: string]: nothing -> nothing {
    let session = get-session $name

    if (is-alive $session.socket) {
        nvim --server $session.socket --remote-send '<C-\><C-N>:qall!<CR>'

        if not (wait-until { not (is-alive $session.socket) }) {
            fail $'The server of ($name) did not stop.' $name --text name
        }
    }

    remove-path $session.socket
    delete-session $name

    print $'Stopped ($name).'
}

# Stop the server of a session and forget the session. Without a name, pick one of the sessions.
def "main kill" [
    name?: string # The session to stop
    --all (-a) # Stop every session
    --force # Stop a session even when it has unsaved changes
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    create-store

    if $all {
        let sessions = list-sessions

        if ($sessions | is-empty) {
            print 'No sessions.'
            return
        }

        if not $force {
            let dirty = $sessions
            | where {|session| is-alive $session.socket }
            | where {|session| has-unsaved-changes $session.name }
            | get name

            if not ($dirty | is-empty) {
                fail $'These sessions have unsaved changes: ($dirty | str join ", "). Save them, or run `nsm kill --all --force`.'
            }
        }

        for session in $sessions {
            stop-session $session.name
        }

        return
    }

    let target = $name | default {|| pick-candidate --sessions --scope $scope }

    if $target == null {
        return
    }

    if not $force and (is-alive (get-socket $target)) and (has-unsaved-changes $target) {
        fail $'The session ($target) has unsaved changes. Save them, or run `nsm kill --force ($target)`.' $name --text session
    }

    stop-session $target
}

# Print the subcommands of nsm.
def main []: nothing -> nothing {
    let usage = [
        'Use `attach` to open a session, `switch` or `last` to change session,'
        '`new` to name one, `list` to list them or `kill` to stop one.'
    ]
    | str join (char nl)

    print $usage
}

# Pick another session and open it.
alias "main s" = main switch

# Return to the previous session.
alias "main l" = main last

# Create or attach to a session.
alias "main a" = main attach

# Create a named session.
alias "main n" = main new

# Print sessions as a table.
alias "main ls" = main list

# Stop a session.
alias "main k" = main kill
