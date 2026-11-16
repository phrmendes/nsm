use std/assert
use ./fixtures.nu [
    from-json
    get-bash
    in-root
    make-dir
    make-file
    make-fzf-shim
    make-shim
    read-file
    run-tests
    with-shim-env
    write-text
]
use ../../cli/picker.nu [list-candidates list-projects pick-candidate]
use ../../cli/store.nu [create-store get-session save-session]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Verify that configured project roots discover repositories under every root and ignore PROJECTS_DIR.
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

# Verify that pick-candidate returns the row that fzf selects, with its data intact.
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
            let picked = with-env {FZF_LOG: $log, FZF_INPUT: $input, FZF_PICK: '2'} {
                pick-candidate --sessions
            }

            let rows = read-file $input | lines
            assert equal ($rows | length) 2 'fzf receives every candidate'
            let decoded = $rows | each {|row| $row | split row (char tab) | get -o 1 | decode base64 | decode | from-json }
            assert equal ($decoded | sort-by name) ($candidates | sort-by name) 'each row carries its candidate as JSON'

            assert equal $picked ($decoded | get -o 1 | get name) 'the second fzf row is returned'
            assert ((read-file $log) =~ '--with-nth 1') 'fzf hides the encoded field'
            assert ((read-file $log) =~ 'nsm preview \{2\}') 'fzf previews the encoded field'
        }
    }
}

# Verify that pick prints JSON rows with the icons and the session state.
def "test pick-prints-json-rows" []: nothing -> nothing {
    in-root {|root|
        let bin = $root | path join bin
        let running_path = $root | path join running
        let stored_path = $root | path join stored
        make-dir $bin
        make-dir $running_path
        make-dir $stored_path
        make-shim ($bin | path join nvim) --interpreter (get-bash)

        with-shim-env $root $bin {
            create-store
            save-session running $running_path
            save-session stored $stored_path
            make-file (get-session running).socket

            let rows = nu --no-config-file cli/main.nu pick --sessions | from-json

            assert equal ($rows | where name == running | first) {
                label: '🟢 running  ~/running'
                name: running
                path: $running_path
                source: running
            } 'a live socket is running'
            assert equal ($rows | where name == stored | first) {
                label: '⚫ stored  ~/stored'
                name: stored
                path: $stored_path
                source: stored
            } 'a missing socket is stored'
        }
    }
}
