use std/assert
use ./fixtures.nu [run-tests]
use ../../cli/render.nu [format-sessions]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Return one session with a long path.
def get-sessions []: nothing -> table {
    [
        {
            name: data-proxy.refactor-implement-projects
            running: true
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
