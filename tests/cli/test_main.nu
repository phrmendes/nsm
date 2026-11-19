use std/assert
use ./fixtures.nu [
    in-root
    in-store
    make-dir
    make-file
    make-shims
    query-store
    read-file
    run-tests
    with-shim-env
]
use ../../cli/store.nu [create-store get-session save-session]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

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

def "test main-last-print-prints-the-socket-of-the-previous-session" []: nothing -> nothing {
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

            let result = nu --no-config-file cli/main.nu last --print | complete

            assert equal $result.exit_code 0 $result.stderr
            assert equal ($result.stdout | str trim) $socket 'the socket of the previous session is printed'
            assert equal (read-file $log | lines | where {|line| $line =~ '--remote-ui' }) [] 'the UI does not open'
            let attached = query-store $db 'select attached_at from sessions where name = :name' --params {name: old} | first
            assert ($attached.attached_at > 20) 'the previous session counts as attached'
        }
    }
}

def "test main-last-print-needs-a-previous-session" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        make-dir $project
        save-session only $project

        let result = nu --no-config-file cli/main.nu last --print | complete

        assert equal $result.exit_code 1 'the command fails'
        assert (($result.stderr | ansi strip) =~ 'There is no previous session.') $result.stderr
    }
}

def "test main-version-follows-the-release-version" []: nothing -> nothing {
    let expected = $'nsm (open .cz.toml | get tool.commitizen.version)'
    let result = nu --no-config-file cli/main.nu --version | complete

    assert equal $result.exit_code 0 $result.stderr
    assert equal ($result.stdout | str trim) $expected 'the version matches .cz.toml'
}

def "test main-names-prints-one-name-per-line" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        make-dir $project
        save-session beta $project
        save-session alpha $project

        let result = nu --no-config-file cli/main.nu names | complete

        assert equal $result.exit_code 0 $result.stderr
        assert equal ($result.stdout | lines | sort) [alpha beta] 'every session name is printed'
    }
}
