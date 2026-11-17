use lib.nu [get-display-path]

# Return the width of the table: the COLUMNS variable, the terminal width, or 80.
def get-width []: nothing -> int {
    if ($env.COLUMNS? | is-not-empty) {
        return ($env.COLUMNS | into int)
    }

    if not (is-terminal --stdout) {
        return 80
    }

    let columns = term size | get columns

    if $columns <= 0 {
        return 80
    }

    $columns
}

# Return the status of a session from the state of its server: `active` or `inactive`.
# A busy server is active.
def get-status [state: string]: nothing -> string {
    match $state {
        running | busy => 'active'
        _ => 'inactive'
    }
}

export def format-sessions [sessions: table]: nothing -> string {
    if ($sessions | is-empty) {
        return 'No sessions yet. Use nsm attach <directory> to start one.'
    }

    $sessions
    | each {|session|
        let status = get-status $session.state

        {
            name: $session.name
            status: $"(if $status == 'active' { '●' } else { '○' }) ($status)"
            path: (get-display-path $session.path)
            attached: (if $session.attached_at == null { 'never' } else { $session.attached_at | into datetime | date humanize })
        }
    }
    | table --width (get-width)
}

export def format-sessions-json [sessions: table]: nothing -> string {
    $sessions
    | each {|session|
        {
            name: $session.name
            path: $session.path
            socket: $session.socket
            status: (get-status $session.state)
            attached_at: (if $session.attached_at == null { null } else { $session.attached_at | into datetime | format date '%+' })
        }
    }
    | to json
}
