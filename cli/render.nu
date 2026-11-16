use store.nu [get-display-path]

# Return the text of a compact table of sessions, or the empty-state message.
export def format-sessions [sessions: table]: nothing -> string {
    if ($sessions | is-empty) {
        return 'No sessions yet. Use nsm attach <directory> to start one.'
    }

    let width = $env.COLUMNS? | default 80 | into int

    $sessions
    | each {|session|
        {
            name: $session.name
            status: (if $session.running { '●' } else { '○' })
            path: (get-display-path $session.path)
            attached: (if $session.attached_at == null { 'never' } else { $session.attached_at | into datetime | date humanize })
        }
    }
    | table --width $width
}
