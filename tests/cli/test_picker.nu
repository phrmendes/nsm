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
use ../../cli/picker.nu [get-preview list-candidates list-projects pick-candidate]
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

# Verify that the scope keeps a directory and its children, never a sibling with the same prefix.
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

# Verify that the preview shows the path, a Files heading, and at most thirty entries.
def "test get-preview-shows-a-directory-listing" []: nothing -> nothing {
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

        let preview = get-preview {name: null, path: $small, source: 'directory'}
        assert equal ($preview | lines | first) $small 'the preview starts with the path'
        assert equal ($preview | lines | skip 1 | take 2) ['Files' ''] 'the heading follows the path'
        assert equal ($preview | lines | skip 3) [alpha.txt beta.txt] 'the entries are listed'

        let limited = get-preview {name: null, path: $large, source: 'directory'}
        assert equal ($limited | lines | skip 3 | length) 30 'only thirty entries are listed'

        let hint = get-preview {name: null, path: $missing, source: 'directory'}
        assert equal ($hint | lines) [$missing '' 'The directory does not exist.']
    }
}
