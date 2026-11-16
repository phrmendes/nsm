use lib.nu [EXIT_UNSAVED fail report-error warn]
use picker.nu [get-preview list-candidates pick-candidate]
use render.nu [format-sessions]
use server.nu [
    connect-session
    get-dirty-sessions
    has-unsaved-changes
    is-alive
    start-session
    stop-session
]
use names.nu [check-name]
use store.nu [
    create-store
    find-session
    get-previous-session-name
    get-session
    list-sessions
    save-session
    touch-session
]

$env.config = ($env.config | upsert error_style 'short')

# Run a command body against the store and report a failure.
def run-command [body: closure]: nothing -> nothing {
    report-error {
        create-store
        do $body
    }
}

# Stop every session, refusing sessions that have unsaved changes unless forced.
def kill-all [force: bool]: nothing -> nothing {
    let sessions = list-sessions

    if ($sessions | is-empty) {
        warn 'No sessions.'
        return
    }

    if not $force {
        let dirty = get-dirty-sessions $sessions

        if ($dirty | is-not-empty) {
            fail $'These sessions have unsaved changes: ($dirty | str join ", "). Save them, or run `nsm kill --all --force`.' --code $EXIT_UNSAVED
        }
    }

    for session in $sessions {
        stop-session $session.name
    }
}

# Stop one session, refusing it when it has unsaved changes unless forced.
def kill-one [target: string, force: bool]: nothing -> nothing {
    let session = get-session $target

    if not $force and (is-alive $session.socket) and (has-unsaved-changes $target) {
        fail $'The session ($target) has unsaved changes. Save them, or run `nsm kill --force ($target)`.' --code $EXIT_UNSAVED
    }

    stop-session $target
}

# Return the description of a subcommand.
def get-summary [name: string]: nothing -> string {
    let command = scope commands | where name == $name | get --optional 0

    if $command == null {
        return ''
    }

    $command.description | str replace --regex '\.$' ''
}

# Pick another session and open it. The picker does not list the current session.
def "main switch" [
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    run-command {
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
    run-command {
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
    run-command {
        connect-session ($target | default {|| pick-candidate --scope $scope })
    }
}

# Create a session with a name of your choice for a directory, and open it.
def "main new" [
    name: string # The name of the session
    path?: path # The directory of the project, the current directory by default
]: nothing -> nothing {
    run-command {
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
    run-command {
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
        let row = try {
            $candidate | decode base64 | decode | from json
        } catch {
            fail 'The preview data is invalid.'
        }

        print (get-preview $row)
    }
}

# Print the rows of the picker as JSON for the Neovim plugin.
def "main pick" [
    --sessions # Only list sessions, not directories
    --scope: string = '' # Only list rows under this directory
]: nothing -> nothing {
    run-command {
        let exclude = $env.NSM_SESSION? | default {|| ''}
        let rows = list-candidates --exclude $exclude --sessions=$sessions --scope $scope

        $rows | to json
    }
}

# Start the server of a session and print its socket. The session counts as attached.
def "main start" [
    target: string # A session name or a directory
]: nothing -> nothing {
    run-command {
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
    run-command {
        if $all {
            kill-all $force
            return
        }

        let target = $name | default {|| pick-candidate --sessions --scope $scope }

        if $target != null {
            kill-one $target $force
        }
    }
}

# Print the subcommands of nsm.
def main []: nothing -> nothing {
    let names = [
        'main attach'
        'main switch'
        'main last'
        'main new'
        'main list'
        'main pick'
        'main start'
        'main preview'
        'main kill'
    ]

    $names
    | each {|name|
        let short = $name | str replace 'main ' ''
        $"  ($short)  (get-summary $name)"
    }
    | str join (char nl)
    | print
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
