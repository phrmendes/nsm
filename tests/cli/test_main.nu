use std/assert
use ./fixtures.nu [
    in-root
    make-dir
    make-shims
    query-store
    read-file
    run-tests
    set-socket
    with-shim-env
]
use ../../cli/store.nu [create-store get-session save-session]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Verify that `new` saves the session and opens it in the current terminal.
def "test main-new-saves-and-opens-the-session" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let project = $root | path join project
        make-dir $project
        let bin = make-shims $root
        let socket = $root | path join nsm demo.sock

        with-shim-env $root $bin {
            create-store

            let result = nu --no-config-file cli/main.nu new demo $project | complete

            assert equal $result.exit_code 0 $result.stderr
            assert equal (get-session demo | select name path) {name: demo, path: $project}

            let calls = read-file $log | lines | where {|line| ($line =~ '--listen') or ($line =~ '--remote-ui') }
            assert equal $calls [
                $'--headless --listen ($socket)'
                $'--server ($socket) --remote-ui'
            ] 'the server starts and the UI attaches'

            let attached = query-store ($root | path join nsm sessions.db) 'select attached_at from sessions' | first
            assert ($attached.attached_at != null) 'the session is attached'
        }
    }
}

# Verify that `last` opens the session that was attached before the current one.
def "test main-last-opens-the-previous-session" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let project = $root | path join project
        make-dir $project
        let bin = make-shims $root
        let socket = $root | path join nsm old.sock

        with-shim-env $root $bin {
            create-store
            save-session old $project
            save-session current $project
            let db = $root | path join nsm sessions.db
            query-store $db 'update sessions set attached_at = 10 where name = :name' --params {name: old} | ignore
            query-store $db 'update sessions set attached_at = 20 where name = :name' --params {name: current} | ignore

            let result = nu --no-config-file cli/main.nu last | complete

            assert equal $result.exit_code 0 $result.stderr
            assert equal (read-file $log | lines | last) $'--server ($socket) --remote-ui' 'the previous session opens'
        }
    }
}

# Verify that `switch` opens the session that the terminal picker returns.
def "test main-switch-opens-the-picked-session" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let fzf_input = $root | path join fzf.input
        let project = $root | path join project
        make-dir $project
        let bin = make-shims $root
        let socket = $root | path join nsm alpha.sock

        with-shim-env $root $bin {
            create-store
            save-session alpha $project

            let result = with-env {FZF_LOG: ($root | path join fzf.log), FZF_INPUT: $fzf_input, FZF_PICK: '1'} {
                nu --no-config-file cli/main.nu switch | complete
            }

            assert equal $result.exit_code 0 $result.stderr
            assert ((read-file $fzf_input) | str contains 'alpha') 'the picker lists the session'
            assert equal (read-file $log | lines | last) $'--server ($socket) --remote-ui' 'the picked session opens'
        }
    }
}
