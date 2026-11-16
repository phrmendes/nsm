use std/assert
use ./fixtures.nu [
    error-message
    finally
    in-root
    in-store
    make-dir
    make-file
    make-setsid-shim
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
use ../../cli/server.nu [get-restore-args has-unsaved-changes is-alive wait-until]
use ../../cli/store.nu [create-store get-session list-sessions save-session]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Verify that start prints the stored socket, starts the server on it, and records the attachment.
def "test start-prints-the-socket-and-records-the-attachment" []: nothing -> nothing {
    in-root {|root|
        let log = $root | path join calls.log
        let project = $root | path join project
        make-dir $project
        let bin_path = make-shims $root

        with-shim-env $root $bin_path {
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

# Verify that kill refuses unsaved changes without --force, and stops clean and forced sessions.
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
            assert ($refused.exit_code != 0) 'kill refuses a dirty session without --force'
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

# Verify that a stopped session gets started and opened, and a running one is only opened.
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

# Verify that a server that cannot answer is an error, not a clean result.
def "test has-unsaved-changes-fails-on-a-dead-socket" []: nothing -> nothing {
    in-store {|root|
        save-session demo $root
        set-socket $root demo ($root | path join missing.sock)

        let message = error-message { has-unsaved-changes demo }

        assert (($message != null) and ($message | str starts-with 'Cannot query the server of demo:')) $'expected a query error in: ($message)'
    }
}

# Verify that a started server runs in the project with the session name in its environment.
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

# Verify that the restore arguments follow the configuration and the file.
def "test get-restore-args-returns-the-configured-session-file" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let file = $project | path join Session.vim
        make-dir $project
        make-file $file

        with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
            assert equal (get-restore-args $project) [] 'no configuration'

            write-text ($root | path join .nsm.nuon) ({restore: {file: 'Session.vim'}} | to nuon)
            assert equal (get-restore-args $project) ['-S' $file] 'a configured file'

            write-text ($root | path join .nsm.nuon) ({restore: {file: 'Missing.vim'}} | to nuon)
            assert equal (get-restore-args $project) [] 'a missing file'

            write-text ($root | path join .nsm.nuon) ({restore: {file: $file}} | to nuon)
            assert equal (get-restore-args $project) ['-S' $file] 'an absolute path'
        }
    }
}

# Verify that a configured session file reaches the server command line.
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

# Verify that kill --all refuses a dirty session and stops every clean one.
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
            assert ($refused.exit_code != 0) 'kill --all refuses a dirty session'
            assert ((($refused.stderr | ansi strip) =~ 'These sessions have unsaved changes: dirty.')) $refused.stderr
            assert (is-alive $clean_socket) 'a refused kill --all keeps every server'

            let forced = nu --no-config-file cli/main.nu kill --all --force | complete
            assert equal $forced.exit_code 0 $forced.stderr
            assert equal ($forced.stdout | lines | sort) ['Stopped clean.' 'Stopped dirty.']
            assert (not (is-alive $clean_socket)) 'the clean server stops'
            assert (not (is-alive $dirty_socket)) 'the dirty server stops'
            assert equal (list-sessions) [] 'every session is gone'
        }

        let empty = nu --no-config-file cli/main.nu kill --all | complete
        assert equal $empty.exit_code 0 $empty.stderr
        assert (((($empty.stderr | ansi strip) =~ '\[W\]') and (($empty.stderr | ansi strip) =~ 'No sessions.'))) $empty.stderr
    }
}
