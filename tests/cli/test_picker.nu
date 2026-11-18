use std/assert
use ./fixtures.nu [
    error-message
    finally
    from-json
    get-bash
    in-root
    in-store
    make-dir
    make-file
    make-fzf-shim
    read-file
    run-tests
    spawn-server
    with-shim-env
    write-text
]
use ../../cli/picker.nu [list-candidates list-projects pick-candidate PREVIEW]
use ../../cli/server.nu [find-server-pid]
use ../../cli/store.nu [create-store get-session save-session]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

def "test list-projects-discovers-repositories-under-configured-roots" []: nothing -> nothing {
    in-root {|root|
        let first_root = $root | path join projects
        let second_root = $root | path join external
        let missing_root = $root | path join missing
        let directories = [
            projects/repo1
            projects/repo2/sub
            projects/.hidden/repo3
            projects/a/b/c
            projects/a/b/c/d
            projects/plain
            projects/wt
            external/repo4
        ]

        for directory in $directories {
            make-dir ($root | path join $directory)
        }

        for directory in [
            projects/repo1
            projects/repo2/sub
            projects/.hidden/repo3
            projects/a/b/c
            projects/a/b/c/d
            external/repo4
        ] {
            make-dir ($root | path join $directory .git)
        }
        make-file ($root | path join projects/wt .git)

        let expected = [
            projects/repo1
            projects/repo2/sub
            projects/.hidden/repo3
            projects/a/b/c
            projects/wt
            external/repo4
        ]
        | each {|directory| $root | path join $directory }
        let config = {
            projects: [$first_root $second_root $first_root $missing_root]
        } | to nuon
        write-text ($root | path join .nsm.nuon) $config

        with-env {XDG_CONFIG_HOME: $root, HOME: $root, PROJECTS_DIR: ($root | path join ignored)} {
            assert equal (list-projects | sort) ($expected | sort) 'repositories under configured roots only'
        }
    }
}

def "test pick-candidate-returns-the-selected-row" []: nothing -> nothing {
    in-root {|root|
        let bin = $root | path join bin
        let log = $root | path join fzf.args
        let input = $root | path join fzf.input
        make-dir $bin
        make-fzf-shim ($bin | path join fzf)

        with-shim-env $root $bin {
            create-store
            save-session alpha $root
            save-session beta $root

            let candidates = list-candidates --sessions
            let picked = with-env {FZF_LOG: $log, FZF_INPUT: $input, FZF_PICK: '2', SHELL: nu} {
                pick-candidate --sessions
            }

            let rows = read-file $input | lines
            assert equal ($rows | length) 2 'fzf receives every candidate'
            let fields = $rows | each {|row| $row | split row (char tab) }
            assert equal ($fields | each { length } | uniq) [3] 'each row has a label, a path, and a name'
            assert equal ($fields | each {|row| {name: $row.2?, path: $row.1?} } | sort-by name) ($candidates | select name path | sort-by name) 'each row carries its path and name'

            assert equal $picked ($fields | get --optional 1 | get --optional 2) 'the second fzf row is returned'
            assert ((read-file $log) =~ '--with-nth 1') 'fzf shows only the label'
            assert ((read-file $log) | str contains 'ls -1 {2}') 'fzf previews the path field'
            assert ((read-file $log) | str contains 'SHELL=/bin/sh') 'fzf runs the preview in a POSIX shell'

            let cancelled = with-env {FZF_LOG: $log, FZF_INPUT: $input, FZF_QUERY: 'zz', FZF_CODE: '1'} {
                pick-candidate --sessions
            }
            assert equal $cancelled null 'a query without a match picks nothing'
        }
    }
}

def "test pick-candidate-reports-an-empty-list" []: nothing -> nothing {
    in-root {|root|
        let bin = $root | path join bin
        make-dir $bin
        make-fzf-shim ($bin | path join fzf)

        with-shim-env $root $bin {
            create-store

            let message = with-env {FZF_LOG: ($root | path join fzf.args), FZF_INPUT: ($root | path join fzf.input), FZF_CODE: '1'} {
                error-message { pick-candidate --sessions }
            }

            assert equal $message 'There is nothing to pick. Start a session with `nsm new <name>`.'
        }
    }
}

def "test pick-candidate-streams-rows-before-slow-sources-finish" []: nothing -> nothing {
    in-root {|root|
        let bin = $root | path join bin
        let bash = get-bash
        make-dir $bin
        write-text ($bin | path join zoxide) ([$"#!($bash)" 'sleep 3'] | str join (char nl))
        write-text ($bin | path join fzf) ([
            $"#!($bash)"
            'IFS= read -r row'
            'printf "\\n%s\\n" "$row"'
        ] | str join (char nl))
        chmod +x ($bin | path join zoxide) ($bin | path join fzf)

        with-shim-env $root $bin {
            create-store
            save-session alpha $root

            let started = date now
            let picked = pick-candidate
            let elapsed = (date now) - $started

            assert equal $picked alpha 'the session row reaches fzf first'
            assert ($elapsed < 1sec) $'fzf got the first row after ($elapsed)'
        }
    }
}

def "test pick-prints-json-rows" []: nothing -> nothing {
    in-root {|root|
        let bin = $root | path join bin
        let running_path = $root | path join running
        let stored_path = $root | path join stored
        make-dir $bin
        make-dir $running_path
        make-dir $stored_path

        with-shim-env $root $bin {
            create-store
            save-session running $running_path
            save-session stored $stored_path
            let socket = (get-session running).socket
            spawn-server $socket
            make-file (get-session stored).socket

            let rows = nu --no-config-file cli/main.nu pick --sessions | from-json

            assert equal ($rows | where name == running | first) {
                label: '🟢 ~/running'
                name: running
                path: $running_path
                source: running
            } 'a listening socket is running'
            assert equal ($rows | where name == stored | first) {
                label: '⚫ ~/stored'
                name: stored
                path: $stored_path
                source: stored
            } 'a socket file without a server is stored'
        }
    }
}

def "test list-candidates-filters-by-scope" []: nothing -> nothing {
    in-root {|root|
        let inside = $root | path join proj
        let deep = $inside | path join app
        let sibling = $root | path join project
        make-dir $deep
        make-dir $sibling

        with-shim-env $root ($root | path join bin) {
            create-store
            save-session inside $inside
            save-session deep $deep
            save-session sibling $sibling

            let by_argument = list-candidates --sessions --scope $inside | get name | sort
            assert equal $by_argument [deep inside] 'the scope and its children stay'
            assert (not ($by_argument | any {|name| $name == sibling})) 'a sibling with the same prefix is dropped'

            with-env {NSM_SCOPE: $sibling} {
                assert equal (list-candidates --sessions | get name) [sibling] 'NSM_SCOPE alone filters'
                assert equal (list-candidates --sessions --scope $inside | get name | sort) [deep inside] 'the argument wins over the variable'
            }
        }
    }
}

def "test preview-shows-a-directory-listing" []: nothing -> nothing {
    in-root {|root|
        let small = $root | path join small
        let large = $root | path join large
        let missing = $root | path join missing
        make-dir $small
        make-dir $large
        make-file ($small | path join alpha.txt)
        make-file ($small | path join beta.txt)
        for index in 1..35 {
            make-file ($large | path join $'file-($index | fill --width 2 --character 0).txt')
        }

        let run = {|path| sh -c ($PREVIEW | str replace --all '{2}' $"'($path)'") | lines }

        let listing = do $run $small
        assert equal ($listing | first) $small 'the preview starts with the path'
        assert equal ($listing | skip 1) [alpha.txt beta.txt] 'the entries follow the path'
        assert equal (do $run $large | skip 1 | length) 30 'only thirty entries are listed'
        assert equal (do $run $missing) [$missing '' 'The directory does not exist.']
    }
}

def "test labels-show-paths-relative-to-the-project-roots" []: nothing -> nothing {
    in-root {|root|
        let projects = $root | path join projects
        let inside = $projects | path join neovim nsm
        let outside = $root | path join elsewhere thesis
        make-dir $inside
        make-dir $outside
        write-text ($root | path join .nsm.nuon) ({projects: [$projects]} | to nuon)

        with-shim-env $root ($root | path join bin) {
            create-store
            save-session nsm $inside
            save-session thesis $outside

            let rows = with-env {XDG_CONFIG_HOME: $root} { list-candidates --sessions }
            let labels = $rows | get label | sort

            assert equal ($labels | get -o 0) '⚫ neovim/nsm' 'a session under the root shows the relative path'
            assert equal ($labels | get -o 1) '⚫ ~/elsewhere/thesis' 'a session outside the root keeps the display path'
            assert equal ($rows | get name | sort) [nsm thesis] 'the rows keep the session names'
        }
    }
}

def "test zoxide-rows-skip-sessions-and-project-roots" []: nothing -> nothing {
    in-root {|root|
        let bin = $root | path join bin
        let projects = $root | path join projects
        let inside = $projects | path join repo
        let outside = 1..8 | each {|index| $root | path join $'dir-($index)' }
        let recent = [$inside] | append $outside
        make-dir $bin
        make-dir ($inside | path join .git)
        for directory in $outside { make-dir $directory }
        write-text ($root | path join .nsm.nuon) ({projects: [$projects]} | to nuon)
        let bash = get-bash
        write-text ($bin | path join zoxide) ([
            $"#!($bash)"
            'printf "%s\n" "$ZOXIDE_DIRS"'
        ] | str join (char nl))
        chmod +x ($bin | path join zoxide)

        with-shim-env $root $bin {
            create-store
            save-session known ($outside | get --optional 0)

            let rows = with-env {
                XDG_CONFIG_HOME: $root
                ZOXIDE_DIRS: ($recent | str join (char nl))
            } { list-candidates }

            let zoxide = $rows | where source == 'zoxide'
            let expected = $outside | skip 1 | take 5
            assert equal ($zoxide | get path) $expected 'project roots and sessions are dropped before the limit'
            assert ($zoxide | all {|row| $row.label | str ends-with ' [Z]' }) 'the tag follows the path'
            assert ($rows | where source != 'zoxide' | all {|row| not ($row.label | str contains '[Z]') }) 'other rows have no tag'
        }
    }
}

def "test stalled-servers-are-listed-at-once" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        make-dir $project
        save-session slow $project
        let socket = (get-session slow).socket
        spawn-server $socket
        let pid = find-server-pid $socket

        finally {|| ^kill -s KILL $pid } {
            ^kill -s STOP $pid

            let started = date now
            let rows = list-candidates --sessions
            let elapsed = (date now) - $started

            assert equal ($rows | where name == slow | get source) [running] 'a stalled server still runs'
            assert ($elapsed < 250ms) $'the picker waited ($elapsed) for a stalled server'
        }
    }
}
