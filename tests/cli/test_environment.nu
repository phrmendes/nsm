use std/assert
use ./fixtures.nu [
    get-bash
    in-root
    make-dir
    make-shims
    run-tests
    with-shim-env
    write-text
]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

def make-tool-shim [path: path, tool: string, body: string]: nothing -> nothing {
    let bash = get-bash

    write-text $path (
        [$"#!($bash)" $"printf '%s\\n' \"($tool) $*\" >> \"$SHIM_LOG\"" $body]
        | str join (char nl)
    )
    chmod +x $path
}

def make-background-setsid-shim [path: path]: nothing -> nothing {
    write-text $path ([$"#!(get-bash)" 'shift' '"$@" &'] | str join (char nl))
    chmod +x $path
}

def make-environment-shims [bin: path]: nothing -> nothing {
    (make-tool-shim
        ($bin | path join direnv)
        direnv
        'shift 2; export ENV_FROM=direnv; exec "$@"'
    )
    (make-tool-shim
        ($bin | path join devenv)
        devenv
        'shift 2; export ENV_FROM=devenv; exec "$@"'
    )
}

def get-environment-answer [nvim_path: path, socket: path]: nothing -> string {
    ^$nvim_path --clean --server $socket --remote-expr '$ENV_FROM' | str trim
}

def "test start-loads-the-direnv-environment" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let bin = make-shims $root
        make-dir $project
        make-environment-shims $bin
        let nvim_path = which nvim | where type == external | get --optional 0.path
        write-text ($project | path join .envrc) ''

        with-shim-env $root $bin {
            let result = nu --no-config-file cli/main.nu start $project | complete

            assert equal $result.exit_code 0 $result.stderr
            assert equal (get-environment-answer $nvim_path ($result.stdout | str trim)) direnv 'the server runs inside direnv'
            assert ($result.stderr | str contains 'Loading the environment of project with direnv') $result.stderr
        }
    }
}

def "test start-loads-devenv-without-an-envrc" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let bin = make-shims $root
        make-dir $project
        make-environment-shims $bin
        let nvim_path = which nvim | where type == external | get --optional 0.path
        write-text ($project | path join devenv.nix) ''

        with-shim-env $root $bin {
            let result = nu --no-config-file cli/main.nu start $project | complete

            assert equal $result.exit_code 0 $result.stderr
            assert equal (get-environment-answer $nvim_path ($result.stdout | str trim)) devenv 'the server runs inside devenv'
        }
    }
}

def "test start-fails-at-once-when-the-environment-is-blocked" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let bin = make-shims $root
        make-dir $project
        make-tool-shim ($bin | path join direnv) direnv 'echo "direnv: error .envrc is blocked" >&2; exit 1'
        make-background-setsid-shim ($bin | path join setsid)
        write-text ($project | path join .envrc) ''

        with-shim-env $root $bin {
            let started = date now
            let result = nu --no-config-file cli/main.nu start $project | complete
            let elapsed = (date now) - $started

            assert equal $result.exit_code 1 'the start fails'
            assert ($result.stderr | str contains 'is blocked') $result.stderr
            assert ($result.stderr | str contains 'did not load') $result.stderr
            assert ($elapsed < 10sec) $'the failure took ($elapsed)'
        }
    }
}

def "test start-fails-at-once-when-another-process-has-the-session-variable" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let bin = make-shims $root
        make-dir $project
        make-tool-shim ($bin | path join direnv) direnv 'sleep 8 >/dev/null 2>&1 & echo "direnv: error .envrc failed" >&2; exit 1'
        make-background-setsid-shim ($bin | path join setsid)
        write-text ($project | path join .envrc) ''

        with-shim-env $root $bin {
            let started = date now
            let result = nu --no-config-file cli/main.nu start $project | complete
            let elapsed = (date now) - $started

            assert equal $result.exit_code 1 'the start fails'
            assert ($result.stderr | str contains 'direnv: error .envrc failed') $result.stderr
            assert ($elapsed < 5sec) $'the failure took ($elapsed)'
        }
    }
}

def "test start-gives-up-after-the-configured-timeout" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let bin = make-shims $root
        make-dir $project
                make-tool-shim ($bin | path join direnv) direnv 'sleep 30'
        make-background-setsid-shim ($bin | path join setsid)
        write-text ($project | path join .envrc) ''
        write-text ($root | path join .nsm.nuon) ({start: {timeout: 1}} | to nuon)

        with-shim-env $root $bin {
            let result = with-env {XDG_CONFIG_HOME: $root} { nu --no-config-file cli/main.nu start $project | complete }

            assert equal $result.exit_code 1 'the start fails'
            assert ($result.stderr | str contains 'did not start within 1 s') $result.stderr
            ^pkill -f $'($bin)/direnv' | complete | ignore
        }
    }
}

def "test start-waits-while-the-launcher-hides-the-socket" []: nothing -> nothing {
    in-root {|root|
        let project = $root | path join project
        let bin = make-shims $root
        make-dir $project
        make-environment-shims $bin
        make-tool-shim ($bin | path join direnv) direnv 'shift 2; export ARGS="$*"; exec bash -c "sleep 3; exec \$ARGS"'
        make-background-setsid-shim ($bin | path join setsid)
        write-text ($project | path join .envrc) ''

        with-shim-env $root $bin {
            let result = nu --no-config-file cli/main.nu start $project | complete

            assert equal $result.exit_code 0 $result.stderr
            assert ($result.stdout | str trim | str ends-with 'project.sock') $result.stdout
        }
    }
}
