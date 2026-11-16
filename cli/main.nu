use lib.nu [fail remove-path report-error warn]
use picker.nu [get-preview list-candidates pick-candidate]
use render.nu [format-sessions]
use server.nu [connect-session has-unsaved-changes is-alive start-session wait-until]
use store.nu [
    check-name
    create-store
    delete-session
    get-previous-session-name
    find-session
    get-session
    list-sessions
    save-session
    touch-session
]

$env.config = ($env.config | upsert error_style 'short')

# Stop the server of a session and forget it.
def stop-session [name: string]: nothing -> nothing {
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

# Pick another session and open it. The picker does not list the current session.
def "main switch" [
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    report-error {
        create-store

        let current = $env.NSM_SESSION?
        let chosen = if $current == null {
            pick-candidate --scope $scope
        } else {
            pick-candidate --exclude $current --scope $scope
        }

        connect-session $chosen
    }
}

# Return to the session that you opened before the current one.
def "main last" []: nothing -> nothing {
    report-error {
        create-store

        let previous = get-previous-session-name

        if $previous == null {
            fail 'There is no previous session.'
        }

        connect-session $previous
    }
}

# Create or attach to a session. The target is a session name or a directory. Without a target, pick one.
def "main attach" [
    target?: string # A session name or a directory
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    report-error {
        create-store

        connect-session ($target | default {|| pick-candidate --scope $scope })
    }
}

# Create a session with a name of your choice for a directory, and open it.
def "main new" [
    name: string # The name of the session
    path?: path # The directory of the project, the current directory by default
]: nothing -> nothing {
    report-error {
        create-store
        check-name $name

        let directory = $path | default $env.PWD | path expand

        if ($directory | path type) != 'dir' {
            fail $'($directory) is not a directory.'
        }

        let existing = find-session $name

        if $existing != null and (is-alive $existing.socket) {
            fail $'The session ($name) is already running.'
        }

        save-session $name $directory | ignore
        connect-session $name
    }
}

# Print a compact table of sessions or a clear empty-state message.
def "main list" []: nothing -> nothing {
    report-error {
        create-store

        let sessions = list-sessions
        | insert running {|session| is-alive $session.socket }

        print (format-sessions $sessions)
    }
}

# Print a candidate preview for fzf.
def "main preview" [
    candidate: string # A candidate row as JSON
]: nothing -> nothing {
    report-error {
        print (get-preview ($candidate | decode base64 | decode | from json))
    }
}

# Print the rows of the picker as JSON for the Neovim plugin.
def "main pick" [
    --sessions # Only list sessions, not directories
    --scope: string = '' # Only list rows under this directory
]: nothing -> nothing {
    report-error {
        create-store

        let exclude = $env.NSM_SESSION? | default ''

        list-candidates --exclude $exclude --sessions=$sessions --scope $scope | to json
    }
}

# Start the server of a session and print its socket. The session counts as attached.
def "main start" [
    target: string # A session name or a directory
]: nothing -> nothing {
    report-error {
        create-store

        let session = (start-session $target)

        touch-session $session.name
        print $session.socket
    }
}

# Stop the server of a session and forget the session. Without a name, pick one of the sessions.
def "main kill" [
    name?: string # The session to stop
    --all (-a) # Stop every session
    --force (-f) # Stop a session even when it has unsaved changes
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    report-error {
        create-store

        if $all {
            let sessions = list-sessions

            if ($sessions | is-empty) {
                warn 'No sessions.'
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

        let session = get-session $target

        if not $force and (is-alive $session.socket) and (has-unsaved-changes $target) {
            fail $'The session ($target) has unsaved changes. Save them, or run `nsm kill --force ($target)`.'
        }

        stop-session $target
    }
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
