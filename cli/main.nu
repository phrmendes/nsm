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

# Create or attach to a session. The target is a session name or a directory. Without a target, pick one.
def "main connect" [
    target?: string # A session name or a directory
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store

    connect-session ($target | default {|| pick-candidate }) --here=$here
}

# Pick another session and open it. The picker does not list the current session.
def "main switch" [
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store

    let current = $env.NSM_SESSION?
    let chosen = if $current == null { pick-candidate } else { pick-candidate --exclude $current }

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

# Attach to a session that exists. Without a name, pick one of the sessions.
def "main attach" [
    name?: string # The session to attach to
    --here # Open the session in the current terminal, not in a kitty tab
]: nothing -> nothing {
    create-store

    let target = $name | default {|| pick-candidate --sessions }

    if $target != null {
        get-session $target | ignore
    }

    connect-session $target --here=$here
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

# Stop the server of a session and forget the session. Without a name, pick one of the sessions.
def "main kill" [
    name?: string # The session to stop
    --force # Stop the session even when it has unsaved changes
]: nothing -> nothing {
    create-store

    let target = $name | default {|| pick-candidate --sessions }

    if $target == null {
        return
    }

    let session = get-session $target

    if (is-alive $session.socket) {
        if not $force and (has-unsaved-changes $target) {
            fail $'The session ($target) has unsaved changes. Save them, or run `nsm kill --force ($target)`.' $name --text session
        }

        nvim --server $session.socket --remote-send '<C-\><C-N>:qall!<CR>'

        if not (wait-until { not (is-alive $session.socket) }) {
            fail $'The server of ($target) did not stop.' $name --text session
        }
    }

    remove-path $session.socket
    delete-session $target

    print $'Stopped ($target).'
}

# Print the subcommands of nsm.
def main []: nothing -> nothing {
    let usage = [
        'Use `connect` to open a session, `switch` or `last` to change session,'
        '`new` to name one, `list` to list them or `kill` to stop one.'
    ]
    | str join (char nl)

    print $usage
}

alias "main c" = main connect
alias "main s" = main switch
alias "main l" = main last
alias "main a" = main attach
alias "main n" = main new
alias "main ls" = main list
alias "main k" = main kill
