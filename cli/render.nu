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

# Return the text of a compact table of sessions, or the empty-state message.
export def format-sessions [sessions: table]: nothing -> string {
    if ($sessions | is-empty) {
        return 'No sessions yet. Use nsm attach <directory> to start one.'
    }

    $sessions
    | each {|session|
        {
            name: $session.name
            status: (match $session.state {
                running => '●'
                busy => '◐'
                _ => '○'
            })
            path: (get-display-path $session.path)
            attached: (if $session.attached_at == null { 'never' } else { $session.attached_at | into datetime | date humanize })
        }
    }
    | table --width (get-width)
}
