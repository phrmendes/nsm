use lib.nu [get-display-path]

# Return the table width from COLUMNS, from the terminal, or 80.
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

# Return the text of the sessions table, or a message when there are no sessions.
export def format-sessions [sessions: table<name: string, path: string, attached_at: oneof<int, nothing>, active: bool>]: nothing -> string {
    if ($sessions | is-empty) {
        return 'No sessions yet. Use nsm attach <directory> to start one.'
    }

    $sessions
    | each {|session|
        {
            name: $session.name
            status: (if $session.active { '● active' } else { '○ inactive' })
            path: (get-display-path $session.path)
            attached: (if $session.attached_at == null { 'never' } else { $session.attached_at | into datetime | date humanize })
        }
    }
    | table --width (get-width)
}

# Return the sessions as JSON with their status and their last attach time.
export def format-sessions-json [sessions: table<name: string, path: string, socket: string, attached_at: oneof<int, nothing>, active: bool>]: nothing -> string {
    $sessions
    | each {|session|
        {
            name: $session.name
            path: $session.path
            socket: $session.socket
            status: (if $session.active { 'active' } else { 'inactive' })
            attached_at: (if $session.attached_at == null { null } else { $session.attached_at | into datetime | format date '%+' })
        }
    }
    | to json
}
