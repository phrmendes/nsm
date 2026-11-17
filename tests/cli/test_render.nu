use std/assert
use ./fixtures.nu [run-tests]
use ../../cli/render.nu [format-sessions]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Return one session with a long path.
def get-sessions []: nothing -> table {
    [
        {
            name: data-proxy.refactor-implement-projects
            state: running
            path: /mnt/external/projects/iplanrio/data-proxy.refactor-implement-projects
            attached_at: null
        }
    ]
}

# Verify that a wide table keeps the whole path on one line.
def "test format-sessions-uses-the-wide-columns" []: nothing -> nothing {
    let path = '/mnt/external/projects/iplanrio/data-proxy.refactor-implement-projects'
    let text = with-env {COLUMNS: 200} { format-sessions (get-sessions) }

    assert ($text | lines | any {|line| $line | str contains $path }) 'the path is on one line'
}

# Verify that a narrow table wraps the path, so the width is respected.
def "test format-sessions-respects-narrow-columns" []: nothing -> nothing {
    let path = '/mnt/external/projects/iplanrio/data-proxy.refactor-implement-projects'
    let wide = with-env {COLUMNS: 200} { format-sessions (get-sessions) | lines | length }
    let narrow = with-env {COLUMNS: 60} { format-sessions (get-sessions) | lines | length }

    let narrow_has_path = with-env {COLUMNS: 60} { format-sessions (get-sessions) }
    | lines
    | any {|line| $line | str contains $path }

    assert ($narrow > $wide) 'a narrow width wraps the columns'
    assert ($narrow_has_path == false) 'the path is split across lines'
}

# Verify that the status column tells active sessions from inactive sessions.
def "test format-sessions-marks-every-state" []: nothing -> nothing {
    let sessions = [
        {
            name: run
            state: running
            path: /tmp/run
            attached_at: null
        }
        {
            name: busy
            state: busy
            path: /tmp/busy
            attached_at: null
        }
        {
            name: off
            state: stopped
            path: /tmp/off
            attached_at: null
        }
    ]

    let text = with-env {COLUMNS: 200} { format-sessions $sessions }

    let rows = $text | lines
    let status = {|name|
        $rows | where {|row| $row | str contains $name } | first
    }

    assert ((do $status run) | str contains '● active') 'a running session is active'
    assert ((do $status busy) | str contains '● active') 'a busy session is active'
    assert ((do $status off) | str contains '○ inactive') 'a stopped session is inactive'
    assert (not ($text | str contains '◐')) 'the table has no half circle'
}
