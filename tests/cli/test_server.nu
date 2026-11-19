use std/assert
use ./fixtures.nu [
    finally
    in-root
    in-store
    make-dir
    make-file
    make-shims
    query-store
    read-file
    run-tests
    set-socket
    spawn-server
    stop-server
    with-shim-env
    write-text
]
use ../../cli/server.nu [
    can-connect
    find-pid-in-ps
    find-server-pid
    get-restore-args
    has-unsaved-changes
    is-alive
    wait-until
]
use ../../cli/store.nu [create-store get-session list-sessions save-session]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

def "test start-prints-the-socket-and-records-the-attachment" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let project = $root | path join project
        make-dir $project
        let bin = make-shims $root

        with-shim-env $root $bin {
            create-store
            save-session demo $project
            let socket = $root | path join custom.sock
            set-socket $root demo $socket

            let result = nu --no-config-file cli/main.nu start demo | complete

            assert equal $result.exit_code 0 $'stdout: ($result.stdout) stderr: ($result.stderr)'
            assert equal ($result.stdout | str trim) $socket 'stdout is the stored socket'
            assert equal (read-file $log | lines | first) $'--headless --listen ($socket)' 'the server starts on the stored socket'

            let attached = query-store ($root | path join nsm sessions.db) 'select attached_at from sessions where name = :name' --params {name: demo} | first
            assert ($attached.attached_at != null) 'the session counts as attached'
        }
    }
}

def "test kill-guards-unsaved-changes" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        let file = $project | path join notes.txt
        let socket = $root | path join dirty.sock
        let clean_socket = $root | path join clean.sock
        make-dir $project
        make-file $file
        save-session dirty $project
        save-session clean $project
        set-socket $root dirty $socket
        set-socket $root clean $clean_socket

        finally {|| stop-server $socket} {
            spawn-server $socket $file
            nvim --server $socket --remote-send '<C-\><C-N>:normal! ix<CR>'
            assert (wait-until { has-unsaved-changes dirty }) 'the buffer is modified'

            let refused = nu --no-config-file cli/main.nu kill dirty | complete
            assert equal $refused.exit_code 3 'kill refuses a dirty session with the unsaved code'
            assert (($refused.stderr =~ 'has unsaved changes')) $refused.stderr
            assert (is-alive $socket) 'a refused kill keeps the server'
            assert equal (get-session dirty | get name) dirty 'a refused kill keeps the session'

            let forced = nu --no-config-file cli/main.nu kill dirty --force | complete
            assert equal $forced.exit_code 0 $forced.stderr
            assert equal ($forced.stdout | str trim) 'Stopped dirty.'
            assert (not (is-alive $socket)) 'a forced kill stops the server'
        }

        finally {|| stop-server $clean_socket} {
            spawn-server $clean_socket

            let stopped = nu --no-config-file cli/main.nu kill clean | complete
            assert equal $stopped.exit_code 0 $stopped.stderr
            assert equal ($stopped.stdout | str trim) 'Stopped clean.' 'a clean session stops'
            assert equal (list-sessions) [] 'every killed session is gone'
        }
    }
}

def "test attach-starts-a-stopped-session-and-reuses-a-running-one" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let project = $root | path join project
        make-dir $project
        let bin = make-shims $root
        let socket = $root | path join nsm project.sock

        with-shim-env $root $bin {
            create-store

            let first = nu --no-config-file cli/main.nu attach $project | complete
            assert equal $first.exit_code 0 $first.stderr
            assert equal (get-session project | select name path) {name: project, path: $project}
            assert equal (read-file $log | lines | where {|line| ($line =~ '--listen') or ($line =~ '--remote-ui') }) [
                $'--headless --listen ($socket)'
                $'--server ($socket) --remote-ui'
            ] 'a missing session starts a server first'

            let again = nu --no-config-file cli/main.nu attach $project | complete
            assert equal $again.exit_code 0 $again.stderr
            assert equal (read-file $log | lines | last) $'--server ($socket) --remote-ui' 'the running session is reused'
            assert equal (read-file $log | lines | where {|line| $line =~ '--headless' } | length) 1 'the server starts once'
        }
    }
}

def "test start-runs-the-server-in-the-project" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        make-dir $project
        save-session demo $project
        let socket = (get-session demo).socket

        finally {|| stop-server $socket} {
            let result = nu --no-config-file cli/main.nu start demo | complete

            assert equal $result.exit_code 0 $result.stderr
            let answer = nvim --clean --server $socket --remote-expr 'getcwd()' | complete
            assert equal ($answer.stdout | str trim) $project 'the server runs in the project'
            let name = nvim --clean --server $socket --remote-expr '$NSM_SESSION' | complete
            assert equal ($name.stdout | str trim) 'demo' 'the server knows its session name'
        }
    }
}

def "test find-pid-in-ps-matches-only-the-listen-socket" []: nothing -> nothing {
    let text = [
        '    1 /sbin/launchd'
        '  42 nvim --headless --listen /s/a.sock -S /p/Session.vim'
        '  43 nvim --headless --listen /s/a.sock2'
        '  44 nvim --headless --listen /s/b.sock'
    ] | str join (char nl)

    let cases = [
        {
            name: 'a socket in the middle of the arguments'
            socket: /s/a.sock
            expected: 42
        }
        {
            name: 'a socket that is the prefix of another one'
            socket: /s/a.sock2
            expected: 43
        }
        {
            name: 'the last line without a final newline'
            socket: /s/b.sock
            expected: 44
        }
        {name: 'a socket without a process', socket: /s/c.sock, expected: null}
        {
            name: 'a path that only the arguments contain'
            socket: /p/Session.vim
            expected: null
        }
    ]

    for case in $cases {
        assert equal (find-pid-in-ps $text $case.socket) $case.expected $case.name
    }

    assert equal (find-pid-in-ps '' /s/a.sock) null 'empty text has no process'
}

def "test can-connect-tells-a-listening-socket-from-a-stale-file" []: nothing -> nothing {
    in-root {|root|
        let live = $root | path join live.sock
        let stale = $root | path join stale.sock
        let missing = $root | path join missing.sock
        let long = $root | path join (1..200 | each { 'x' } | str join) | $in + '.sock'
        make-file $stale

        finally {|| stop-server $live} {
            spawn-server $live

            assert (can-connect $live) 'a listening socket accepts a connection'
            assert (not (can-connect $stale)) 'a file that is not a socket does not'
            assert (not (can-connect $missing)) 'a missing path does not'
            assert (not (can-connect $long)) 'a path that is too long for a socket does not'
        }
    }
}

def "test start-does-not-leak-inherited-files" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        let leak = $root | path join leak.txt
        make-dir $project
        write-text $leak 'x'
        save-session demo $project
        let socket = (get-session demo).socket

        finally {|| stop-server $socket} {
            let script = $'exec 9<($leak); exec nu --no-config-file cli/main.nu start demo'
            let result = bash -c $script | complete

            assert equal $result.exit_code 0 $result.stderr
            # Wait for the end of the startup, while Neovim still opens and closes files.
            nvim --clean --server $socket --remote-expr '1' | complete | ignore
            let pid = find-server-pid $socket
            let held = if $nu.os-info.name == 'macos' {
                ^lsof -p $pid | lines | where {|line| $line | str ends-with $leak }
            } else {
                ls -l $'/proc/($pid)/fd' | where target == $leak
            }

            assert equal ($held | length) 0 'the server does not hold a file of its parent'
        }
    }
}

def "test start-passes-the-restore-file-to-the-server" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let project = $root | path join project
        let file = $project | path join Session.vim
        make-dir $project
        make-file $file
        write-text ($root | path join .nsm.nuon) ({restore: {file: 'Session.vim'}} | to nuon)
        let bin = make-shims $root

        with-shim-env $root $bin {
            create-store
            save-session demo $project

            let result = with-env {XDG_CONFIG_HOME: $root} {
                nu --no-config-file cli/main.nu start demo | complete
            }

            assert equal $result.exit_code 0 $result.stderr
            assert equal (read-file $log | lines | first) $'--headless --listen ($root | path join nsm demo.sock) -S ($file)' 'the server restores the session file'
        }
    }
}

# End a server with a KILL signal, also when it is stalled.
def end-server [socket: path]: nothing -> nothing {
    let pid = find-server-pid $socket

    if $pid != null {
        ^kill -s KILL $pid | complete | ignore
    }
}

def "test kill-handles-a-stalled-server" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        let socket = $root | path join stalled.sock
        make-dir $project
        save-session stalled $project
        set-socket $root stalled $socket

        finally {|| end-server $socket} {
            spawn-server $socket
            let pid = find-server-pid $socket
            assert ($pid != null) 'the server process is found by its socket'
            assert equal (find-server-pid ($root | path join unused.sock)) null 'an unused socket has no process'

            ^kill -s STOP $pid
            let started = date now
            let refused = nu --no-config-file cli/main.nu kill stalled | complete

            assert equal $refused.exit_code 3 'a stalled server is refused with the unsaved code'
            assert ($refused.stderr =~ 'does not answer') $refused.stderr
            assert ((date now) - $started < 6sec) 'the refusal does not wait for long'
            assert equal (get-session stalled | get name) stalled 'a refused kill keeps the session'

            let forced_started = date now
            let forced = nu --no-config-file cli/main.nu kill stalled --force | complete

            assert equal $forced.exit_code 0 $forced.stderr
            assert ((date now) - $forced_started < 8sec) 'a forced kill ends a stopped server without polling for the signal'
            assert (not ($socket | path exists)) 'a forced kill removes the socket'
            assert equal (find-server-pid $socket) null 'a forced kill ends the process'
            assert equal (list-sessions) [] 'a forced kill forgets the session'
            assert ((date now) - $started < 12sec) 'a forced kill does not hang'
        }
    }
}

def "test list-does-not-wait-on-stalled-servers" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        let first = $root | path join first.sock
        let second = $root | path join second.sock
        make-dir $project
        save-session first $project
        save-session second $project
        set-socket $root first $first
        set-socket $root second $second

        finally {|| end-server $first; end-server $second} {
            spawn-server $first
            spawn-server $second
            ^kill -s STOP (find-server-pid $first)
            ^kill -s STOP (find-server-pid $second)

            let started = date now
            let result = nu --no-config-file cli/main.nu list | complete
            let elapsed = (date now) - $started

            assert equal $result.exit_code 0 $result.stderr
            assert equal ($result.stdout | lines | where {|line| $line | str contains '● active' } | length) 2 'a stalled server counts as active'
            assert ($elapsed < 250ms) $'list waited ($elapsed) for stalled servers'
        }
    }
}

def "test kill-all-stops-clean-sessions-and-refuses-dirty-ones" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        let file = $project | path join notes.txt
        make-dir $project
        make-file $file
        save-session clean $project
        save-session dirty $project
        let clean_socket = $root | path join clean.sock
        let dirty_socket = $root | path join dirty.sock
        set-socket $root clean $clean_socket
        set-socket $root dirty $dirty_socket

        finally {|| stop-server $dirty_socket} {
            spawn-server $clean_socket
            spawn-server $dirty_socket $file
            nvim --server $dirty_socket --remote-send '<C-\><C-N>:normal! ix<CR>'
            assert (wait-until { has-unsaved-changes dirty }) 'the buffer is modified'

            let refused = nu --no-config-file cli/main.nu kill --all | complete
            assert equal $refused.exit_code 3 'kill --all refuses a dirty session with the unsaved code'
            assert ((($refused.stderr | ansi strip) =~ 'These sessions have unsaved changes: dirty.')) $refused.stderr
            assert (is-alive $clean_socket) 'a refused kill --all keeps every server'

            let forced = nu --no-config-file cli/main.nu kill --all --force | complete
            assert equal $forced.exit_code 0 $forced.stderr
            assert equal ($forced.stdout | lines | sort) ['Stopped clean.' 'Stopped dirty.']
            assert (not (is-alive $clean_socket)) 'the clean server stops'
            assert (not (is-alive $dirty_socket)) 'the dirty server stops'
            assert equal (list-sessions) [] 'every session is gone'
        }

        let missing = nu --no-config-file cli/main.nu kill ghost | complete
        assert equal $missing.exit_code 1 'another failure keeps the generic code'
        assert ((($missing.stderr | ansi strip) =~ 'No session is named ghost.')) $missing.stderr

        let empty = nu --no-config-file cli/main.nu kill --all | complete
        assert equal $empty.exit_code 0 $empty.stderr
        assert (((($empty.stderr | ansi strip) =~ '\[W\]') and (($empty.stderr | ansi strip) =~ 'No sessions.'))) $empty.stderr
    }
}
