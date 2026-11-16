use std/assert
use ../../cli/lib.nu [remove-path]
use ./fixtures.nu [
    error-message
    in-store
    make-dir
    make-file
    make-shim
    query-store
    write-text
]
use ../../cli/config.nu [get-config]
use ../../cli/picker.nu [get-preview list-candidates list-projects pick-candidate]
use ../../cli/server.nu [connect-session get-restore-args has-unsaved-changes is-alive wait-until]
use ../../cli/render.nu [format-sessions]
use ../../cli/store.nu [
    check-name
    create-store
    delete-session
    get-display-path
    get-free-name
    get-previous-session-name
    get-session
    get-session-name
    list-sessions
    resolve-target
    save-session
    touch-session
]

def main []: nothing -> nothing {
    print '🧪 Running tests...'

    let cmds = (
        scope commands
        | where ($it.type == 'custom')
            and ($it.name | str starts-with 'test ')
            and not ($it.description | str starts-with 'ignore')
        | get name
        | each {|test| [$"print '🔹 Running test: ($test)'" $test] }
        | flatten
        | str join '; '
    )

    nu --no-config-file --commands $'source ($env.CURRENT_FILE); ($cmds)'
    print '✅ Tests completed successfully'
}

# Verify the default CLI help text.
def "test main-prints-exact-help" []: nothing -> nothing {
    let result = nu --no-config-file cli/main.nu | complete
    let expected = [
        'Use `attach` to open a session, `switch` or `last` to change session,'
        '`new` to name one, `list` to list them or `kill` to stop one.'
    ] | str join (char nl)

    assert equal $result.exit_code 0 $result.stderr
    assert equal ($result.stdout | str trim) $expected
}

# Verify valid names and exact rejection messages for invalid names.
def "test check-name-covers-valid-and-invalid-inputs" []: nothing -> nothing {
    let cases = [
        [name, valid, expected_error];
        ['letters', alpha, null]
        ['digits', '42', null]
        ['dot and dash', a.b-c, null]
        ['underscore', _work, null]
        ['single dot', ., null]
        ['double dot', .., null]
        ['empty', '', 'A session name may only hold letters, digits, dots, dashes and underscores.']
        ['space', 'a b', 'A session name may only hold letters, digits, dots, dashes and underscores.']
        ['slash', 'a/b', 'A session name may only hold letters, digits, dots, dashes and underscores.']
        ['colon', 'a:b', 'A session name may only hold letters, digits, dots, dashes and underscores.']
        ['backslash', 'a\b', 'A session name may only hold letters, digits, dots, dashes and underscores.']
        ['unicode letter', 'café', 'A session name may only hold letters, digits, dots, dashes and underscores.']
    ]

    for case in $cases {
        let error = error-message { check-name $case.valid }
        assert equal $error $case.expected_error $case.name
    }
}

# Verify base selection, collision suffixes, gaps, and a long collision run.
def "test get-free-name-selects-the-first-available-candidate" []: nothing -> nothing {
    let exhausted = ['app'] | append (2..1000 | each {|suffix| $'app-($suffix)' })
    let cases = [
        [name, base, taken, expected];
        ['base is free', app, [], app]
        ['unrelated name is taken', app, [other], app]
        ['base is taken', app, [app], app-2]
        ['first suffix is taken', app, [app app-2], app-3]
        ['a gap wins', app, [app app-3], app-2]
        ['suffixes continue beyond one thousand', app, $exhausted, app-1001]
    ]

    for case in $cases {
        assert equal (get-free-name $case.base ...$case.taken) $case.expected $case.name
    }
}

# Verify home abbreviation at path boundaries and preserve unrelated paths.
def "test get-display-path-abbreviates-only-home-descendants" []: nothing -> nothing {
    let cases = [
        [name, path, expected];
        ['home itself', /home/ana, '~']
        ['child of home', /home/ana/project, '~/project']
        ['deep child of home', /home/ana/project/src, '~/project/src']
        ['sibling shares home prefix', /home/anabel/project, /home/anabel/project]
        ['home text occurs later', /srv/home/ana/project, /srv/home/ana/project]
        ['unrelated path', /srv/project, /srv/project]
    ]

    with-env {HOME: /home/ana} {
        for case in $cases {
            assert equal (get-display-path $case.path) $case.expected $case.name
        }
    }
}

# Verify name sanitization for directory basenames outside Git repositories.
def "test get-session-name-sanitizes-non-git-directory-names" []: nothing -> nothing {
    let root = mktemp --directory
    let cases = [
        [directory, expected];
        [notes, notes]
        ['my project!', 'my-project-']
        ['api_v2-1.0', api_v2-1.0]
        ['a@b#c', a-b-c]
    ]

    for case in $cases {
        let directory = $root | path join $case.directory
        make-dir $directory
        assert equal (get-session-name $directory) $case.expected $case.directory
    }

    remove-path $root
}

# Verify Git root naming for the repository and nested directories.
def "test get-session-name-uses-git-root-for-all-descendants" []: nothing -> nothing {
    let root = mktemp --directory
    let repository = $root | path join 'my repo'
    let paths = [
        $repository
        ($repository | path join src)
        ($repository | path join src nested)
    ]

    for path in $paths {
        make-dir $path
    }
    git init --quiet $repository

    for path in $paths {
        assert equal (get-session-name $path) 'my-repo' $path
    }

    remove-path $root
}

# Verify a saved session returns its full row and an unknown name gives the expected error.
def "test get-session-returns-record-or-specific-error" []: nothing -> nothing {
    in-store {|root|
        save-session work $root

        assert equal (get-session work) {
            name: work
            path: $root
            socket: (get-session work).socket
        }
        assert equal (error-message { get-session ghost }) 'No session is named ghost.'
    }
}

# Verify target resolution by session name, saved path, new path, and colliding basename.
def "test resolve-target-resolves-names-and-paths" []: nothing -> nothing {
    in-store {|root|
        let known_path = $root | path join known
        let new_path = $root | path join fresh
        let first_collision = $root | path join one notes
        let second_collision = $root | path join two notes
        make-dir $known_path
        make-dir $new_path
        make-dir $first_collision
        make-dir $second_collision
        save-session journal $known_path
        save-session notes $first_collision

        let cases = [
            [name target expected];
            ['saved name' journal {name: journal, path: $known_path}]
            ['saved directory' $known_path {name: journal, path: $known_path}]
            ['new directory' $new_path {name: fresh, path: $new_path}]
            ['colliding basename' $second_collision {name: notes-2, path: $second_collision}]
        ]

        for case in $cases {
            assert equal (resolve-target $case.target) $case.expected $case.name
        }
    }

    in-store {|root|
        let first = $root | path join one notes
        let second = $root | path join two notes
        make-dir $first
        make-dir $second
        save-session notes $first

        assert equal (resolve-target $second) {name: notes-2, path: $second} 'colliding basenames get a free suffix'
    }
}

# Verify missing and file targets fail with a directory-specific error.
def "test resolve-target-rejects-missing-and-file-targets" []: nothing -> nothing {
    in-store {|root|
        let db = $root | path join nsm sessions.db
        let missing = $root | path join absent
        let cases = [
            [name target];
            ['existing file' $db]
            ['missing path' $missing]
        ]

        for case in $cases {
            let message = error-message { resolve-target $case.target }
            assert (($message | default 'missing') =~ 'is not a directory') $case.name
        }
    }
}

# Verify initialization and migration for legacy, unattached, current, and repeat runs.
def "test create-store-migrates-only-legacy-attachment-times" []: nothing -> nothing {
    let cases = [
        [name, version, attached, expected];
        ['legacy timestamp', 0, 1700000000, 1_700_000_000_000_000_000]
        ['legacy null timestamp', 0, null, null]
        ['current version stays unchanged', 1, 1700000000, 1700000000]
    ]

    for case in $cases {
        in-store {|root|
            let db = $root | path join nsm sessions.db
            save-session work $root
            query-store $db $'pragma user_version = ($case.version)' | ignore
            query-store $db 'update sessions set attached_at = :time where name = :name' --params {
                time: $case.attached
                name: work
            } | ignore

            create-store
            create-store

            let session = query-store $db 'select attached_at from sessions' | first
            let version = query-store $db 'select user_version from pragma_user_version' | first

            assert equal $session.attached_at $case.expected $case.name
            assert equal $version.user_version 1 'store schema version'
        }
    }
}

# Verify session updates preserve creation and attachment metadata while changing the path.
def "test save-session-updates-path-and-preserves-metadata" []: nothing -> nothing {
    in-store {|root|
        let first_path = $root | path join first
        let second_path = $root | path join second
        make-dir $first_path
        make-dir $second_path

        save-session work $first_path
        let db = $root | path join nsm sessions.db
        let first = query-store $db 'select * from sessions' | first
        let custom_socket = $root | path join custom.sock
        query-store $db 'update sessions set socket = :socket, attached_at = 123 where name = :name' --params {name: work, socket: $custom_socket} | ignore
        save-session work $second_path
        let updated = query-store ($root | path join nsm sessions.db) 'select * from sessions' | first

        assert equal $updated.path $second_path 'updated project path'
        assert equal $updated.socket $custom_socket 'custom socket path stays unchanged'
        assert equal $updated.created_at $first.created_at 'creation time stays unchanged'
        assert equal $updated.attached_at 123 'attachment time stays unchanged'
    }
}

# Verify list ordering, attachment updates, and deletion through observable database rows.
def "test session-list-touch-and-delete" []: nothing -> nothing {
    in-store {|root|
        save-session zeta $root
        save-session alpha $root
        assert equal (list-sessions | get name) [alpha zeta] 'sessions sort by name'

        query-store ($root | path join nsm sessions.db) 'update sessions set attached_at = 1 where name = :name' --params {name: alpha} | ignore
        touch-session alpha
        let attached = query-store ($root | path join nsm sessions.db) 'select attached_at from sessions where name = :name' --params {name: alpha} | first
        assert ($attached.attached_at > 1) 'touch-session records a new attachment time'

        delete-session alpha
        assert equal (list-sessions | get name) [zeta] 'delete-session removes only the selected row'
        assert equal (error-message { get-session alpha }) 'No session is named alpha.'
    }
}

# Verify that last-session selection handles zero, one, two, and several attachments.
def "test previous-session-selection-skips-unattached-sessions" []: nothing -> nothing {
    let cases = [
        [name, attached, expected];
        ['no sessions', [], null]
        ['one attachment', [
            {name: only, time: 10}
        ], null]
        ['two attachments', [
            {name: old, time: 10}
            {name: current, time: 20}
        ], old]
        ['several attachments', [
            {name: old, time: 10}
            {name: middle, time: 20}
            {name: current, time: 30}
        ], middle]
        ['unattached session is ignored', [
            {name: old, time: 10}
            {name: stored, time: null}
            {name: current, time: 20}
        ], old]
    ]

    for case in $cases {
        in-store {|root|
            let db = $root | path join nsm sessions.db

            for session in $case.attached {
                save-session $session.name $root
                if $session.time != null {
                    query-store $db 'update sessions set attached_at = :time where name = :name' --params {
                        time: $session.time
                        name: $session.name
                    } | ignore
                }
            }

            assert equal (get-previous-session-name) $case.expected $case.name
        }
    }
}

# Verify empty output, status markers, paths, and attached/unattached labels.
def "test format-sessions-renders-state-cases" []: nothing -> nothing {
    assert equal (format-sessions []) 'No sessions yet. Use nsm attach <directory> to start one.'

    let now = date now | into int
    let cases = [
        {
            name: 'running session in home'
            session: {
                name: api
                path: /home/test/api
                running: true
                attached_at: $now
            }
            expected: ['api' '●' '~/api' 'now']
        }
        {
            name: 'stored session without attachment'
            session: {
                name: docs
                path: /tmp/docs
                running: false
                attached_at: null
            }
            expected: ['docs' '○' '/tmp/docs' 'never']
        }
    ]

    with-env {HOME: /home/test} {
        for case in $cases {
            let text = format-sessions [$case.session]
            for expected in $case.expected {
                assert ($text =~ $expected) $'($case.name): expected ($expected) in ($text)'
            }
        }
    }
}

# Verify the CLI list command renders an empty store without starting a server.
def "test main-list-renders-empty-store" []: nothing -> nothing {
    let root = mktemp --directory

    with-env {XDG_STATE_HOME: $root, HOME: $root} {
        let result = nu --no-config-file cli/main.nu list | complete
        assert equal $result.exit_code 0 $result.stderr
        assert (($result.stdout | str trim) =~ 'No sessions yet.') $result.stdout
    }

    remove-path $root
}

# Verify invalid new-session paths fail before they create a database record.
def "test main-new-rejects-file-without-saving-session" []: nothing -> nothing {
    in-store {|root|
        let db = $root | path join nsm sessions.db
        let result = nu --no-config-file cli/main.nu new demo $db | complete

        assert ($result.exit_code != 0) 'nsm new must reject a file path'
        assert (($result.stderr =~ 'is not a directory')) $result.stderr
        assert equal (query-store $db 'select name from sessions') [] 'invalid path must not persist a session'
    }
}

# Verify that `new` checks the socket stored for an existing session.
def "test main-new-checks-the-stored-socket" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let project = $root | path join project
    let custom_socket = $root | path join custom.sock
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $project
    make-shim ($bin | path join nvim) --interpreter $bash

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
    } {
        create-store
        save-session demo $project
        query-store ($root | path join nsm sessions.db) 'update sessions set socket = :socket where name = :name' --params {name: demo, socket: $custom_socket} | ignore
        make-file $custom_socket

        let result = nu --no-config-file cli/main.nu new demo $project | complete

        assert ($result.exit_code != 0) 'new refuses a running session'
        assert (($result.stderr =~ 'already running')) $result.stderr
        assert (open $log | lines | any {|line| $line =~ $custom_socket }) 'liveness uses the stored socket'
    }

    remove-path $root
}

# Verify that configured project roots discover repositories under every path and ignore PROJECTS_DIR.
def "test list-projects-discovers-repositories-under-configured-roots" []: nothing -> nothing {
    let root = mktemp --directory
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

    remove-path $root
}

# Verify that zoxide rows have a distinct source, label, and top-five limit.
def "test list-candidates-labels-the-top-five-zoxide-rows" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let zoxide_dirs = 1..7 | each {|index| $root | path join $'zoxide-($index)' }
    let zoxide_shim = $bin | path join zoxide
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    $zoxide_dirs | each {|directory| make-dir $directory }
    write-text $zoxide_shim ([
        $'#!($bash)'
        'printf "%s\\n" "$ZOXIDE_DIRS"'
    ] | str join (char nl))
    chmod +x $zoxide_shim

    with-env {
        XDG_CONFIG_HOME: $root
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        ZOXIDE_DIRS: ($zoxide_dirs | str join (char nl))
    } {
        let rows = nu --no-config-file cli/main.nu pick | from json | where source == 'zoxide'
        assert equal ($rows | length) 5 'only the top five zoxide paths appear'
        assert equal ($rows | get path) ($zoxide_dirs | take 5) 'zoxide ranking stays ordered'
        assert (($rows | get label | all {|label| $label | str starts-with '[Z] 📁 ' })) 'zoxide labels carry the source marker'
    }

    remove-path $root
}

# Verify that the CLI picker sends zoxide rows to fzf with their selection data.
def "test pick-candidate-uses-fzf-with-zoxide-rows" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join fzf.args
    let input = $root | path join fzf.input
    let zoxide_dir = $root | path join zoxide-dir
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    let path = [$bin] | append $env.PATH | str join (char esep)
    make-dir $bin
    make-dir $zoxide_dir

    let zoxide_shim = [
        $'#!($bash)'
        'printf "%s\\n" "$ZOXIDE_DIR"'
    ] | str join (char nl)
    write-text ($bin | path join zoxide) $zoxide_shim
    chmod +x ($bin | path join zoxide)

    let fzf_shim = [
        $'#!($bash)'
        'printf "%s\\n" "$*" > "$FZF_LOG"'
        'cat > "$FZF_INPUT"'
        'printf "%s\\n" "$FZF_SELECTION"'
    ] | str join (char nl)
    write-text ($bin | path join fzf) $fzf_shim
    chmod +x ($bin | path join fzf)

    with-env {XDG_CONFIG_HOME: $root, XDG_STATE_HOME: $root, HOME: $root, PATH: $path, ZOXIDE_DIR: $zoxide_dir} {
        create-store
        let candidate = list-candidates | where source == 'zoxide' | first
        let selection = [$candidate.label ($candidate | to json --raw)] | str join (char tab)

        let picked = with-env {FZF_LOG: $log, FZF_INPUT: $input, FZF_SELECTION: $selection} {
            pick-candidate
        }

        assert equal $picked $zoxide_dir 'selected zoxide path'
        assert (open $input | str contains '[Z]') 'zoxide rows appear in fzf'
        assert (not (open $log | str contains 'ctrl-z')) 'fzf has no zoxide toggle binding'
    }

    remove-path $root
}

# Verify that connecting opens the session UI in the current terminal.
def "test connect-session-opens-the-current-terminal" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let project = $root | path join project
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $project
    make-shim ($bin | path join nvim) --interpreter $bash

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
    } {
        create-store
        save-session demo $project
        let socket = $root | path join custom.sock
        query-store ($root | path join nsm sessions.db) 'update sessions set socket = :socket where name = :name' --params {name: demo, socket: $socket} | ignore
        make-file $socket
        connect-session demo
    }

    let calls = open $log | lines
    let socket = $'($root)/custom.sock'
    let ui = $calls | where { ($in =~ '--remote-ui') and ($in =~ $socket) } | first
    assert ($ui != null) 'the UI attaches to the session socket in the current terminal'

    remove-path $root
}

# Verify that pick prints JSON rows with the icons and the session state.
def "test pick-prints-json-rows" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let running_path = $root | path join running
    let stored_path = $root | path join stored
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $running_path
    make-dir $stored_path
    make-shim ($bin | path join nvim) --interpreter $bash

    let rows = with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
    } {
        create-store
        save-session running $running_path
        save-session stored $stored_path
        make-file (get-session running).socket

        nu --no-config-file cli/main.nu pick --sessions | from json
    }

    let running = $rows | where name == running | first
    let stored = $rows | where name == stored | first

    assert equal $running.label '🟢 running  ~/running' 'a running session uses the running icon'
    assert equal $running.source running 'a live socket is running'
    assert equal $stored.label '⚫ stored  ~/stored' 'a stopped session uses the stored icon'
    assert equal $stored.source stored 'a missing socket is stored'

    remove-path $root
}

# Verify that start prints the socket and records the attachment without a tab.
def "test start-prints-the-socket-and-records-the-attachment" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let project = $root | path join project
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $project
    let setsid_shim = $bin | path join setsid
    write-text $setsid_shim ([$'#!($bash)' 'shift' 'exec "$@"'] | str join (char nl))
    chmod +x $setsid_shim

    let nvim_shim = $bin | path join nvim
    let shim = [
        $'#!($bash)'
        'printf \'%s\\n\' "$*" >> "$SHIM_LOG"'
        'previous=""'
        'for arg in "$@"; do'
        '  if [ "$previous" = "--listen" ]; then : > "$arg"; fi'
        '  previous="$arg"'
        'done'
    ] | str join (char nl)
    write-text $nvim_shim $shim
    chmod +x $nvim_shim

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
    } {
        create-store
        save-session demo $project
        let socket = $root | path join custom.sock
        query-store ($root | path join nsm sessions.db) 'update sessions set socket = :socket where name = :name' --params {name: demo, socket: $socket} | ignore

        let result = nu --no-config-file cli/main.nu start demo | complete

        assert equal $result.exit_code 0 $'stdout: ($result.stdout) stderr: ($result.stderr)'
        assert equal ($result.stdout | str trim) $socket 'stdout is the stored socket'
        assert (open $log | lines | any {|line| ($line =~ '--listen') and ($line =~ $socket) }) 'server starts on the stored socket'

        let attached = query-store ($root | path join nsm sessions.db) 'select attached_at from sessions where name = :name' --params { name: demo } | first
        assert ($attached.attached_at != null) 'the session counts as attached'
    }

    remove-path $root
}

# Verify that kill refuses unsaved changes without --force, and stops the server with it.
def "test kill-guards-unsaved-changes" []: nothing -> nothing {
    in-store {|root|
        let project = $root | path join project
        let file = $project | path join notes.txt
        make-dir $project
        make-file $file
        save-session demo $project
        let socket = $root | path join custom.sock
        query-store ($root | path join nsm sessions.db) 'update sessions set socket = :socket where name = :name' --params {name: demo, socket: $socket} | ignore

        job spawn { nvim --headless --listen $socket $file }

        assert (wait-until { is-alive $socket }) 'server started'
        nvim --server $socket --remote-send '<C-\><C-N>:normal! ix<CR>'
        assert (wait-until { has-unsaved-changes demo }) 'buffer is modified'

        let refused = nu --no-config-file cli/main.nu kill demo | complete
        assert ($refused.exit_code != 0) 'kill refuses without --force'
        assert (($refused.stderr =~ 'unsaved changes')) $refused.stderr
        assert (is-alive $socket) 'refused kill keeps the server'

        let forced = nu --no-config-file cli/main.nu kill demo --force | complete
        assert equal $forced.exit_code 0 $forced.stderr
        assert (not (is-alive $socket)) 'forced kill stops the server'
        assert equal (list-sessions) [] 'forced kill removes the session'
    }
}

# Verify that attach creates a missing session.
def "test attach-creates-missing-session" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let project = $root | path join project
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $project
    make-shim ($bin | path join nvim) --interpreter $bash

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
    } {
        create-store
        make-file ($root | path join nsm project.sock)

        let result = nu --no-config-file cli/main.nu attach $project | complete

        assert equal $result.exit_code 0 $result.stderr
        assert equal (get-session project | get path) $project
    }

    remove-path $root
}

# Verify that the short commands forward to the full commands.
def "test short-commands-forward-to-full-commands" []: nothing -> nothing {
    let root = mktemp --directory

    with-env {XDG_STATE_HOME: $root, HOME: $root} {
        let listed = nu --no-config-file cli/main.nu ls | complete
        assert equal $listed.exit_code 0 $listed.stderr
        assert (($listed.stdout | str trim) =~ 'No sessions yet.') $listed.stdout

        let previous = nu --no-config-file cli/main.nu l | complete
        assert ($previous.exit_code != 0) 'l must fail without a previous session'
        assert (($previous.stderr =~ 'There is no previous session.')) $previous.stderr
    }

    remove-path $root
}

# Verify that kill --all removes every session and its socket.
def "test kill-all-stops-every-session" []: nothing -> nothing {
    in-store {|root|
        save-session one $root
        save-session two $root

        let result = nu --no-config-file cli/main.nu k -a | complete

        assert equal $result.exit_code 0 $result.stderr
        assert equal (list-sessions) [] 'every session is gone'
        assert (($result.stdout =~ 'Stopped one') and ($result.stdout =~ 'Stopped two')) $result.stdout
        assert (not (($root | path join nsm one.sock) | path exists)) 'socket is removed'

        let empty = nu --no-config-file cli/main.nu k -a -f | complete
        assert equal $empty.exit_code 0 $empty.stderr
        assert (($empty.stderr =~ '\[W\]') and ($empty.stderr =~ 'No sessions.')) $empty.stderr
    }
}

# Verify that the preview shows the path, a Files heading, and the directory entries.
def "test get-preview-lists-files" []: nothing -> nothing {
    let root = mktemp --directory
    make-dir ($root | path join project)
    make-file ($root | path join project notes.txt)

    let preview = get-preview {name: null, path: ($root | path join project), source: 'directory'}

    assert ($preview =~ 'Files') 'expected a Files heading'
    assert ($preview =~ 'notes.txt') 'expected the file name'
    assert (not ($preview =~ 'directory')) 'expected no source word'

    remove-path $root
}

# Verify that preview prints the preview of one JSON row.
def "test preview-prints-the-preview-of-one-row" []: nothing -> nothing {
    let root = mktemp --directory
    let project = $root | path join project
    make-dir $project
    make-file ($project | path join notes.txt)
    let row = {name: null, path: $project, source: directory} | to json --raw

    let result = nu --no-config-file cli/main.nu preview $row | complete

    assert equal $result.exit_code 0 $result.stderr
    assert (
        ($result.stdout | str contains $project) and ($result.stdout | str contains 'notes.txt')
    ) $result.stdout

    remove-path $root
}

# Verify that a missing configuration file gives the defaults.
def "test get-config-defaults-without-a-file" []: nothing -> nothing {
    let root = mktemp --directory

    with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
        let config = get-config

        assert equal $config.projects []
        assert equal $config.icons.running '🟢'
        assert equal $config.icons.stored '⚫'
        assert equal $config.icons.directory '📁'
        assert equal $config.restore.file null
    }

    remove-path $root
}

# Verify that the file sets a project path list and overrides single icons.
def "test get-config-reads-project-paths-and-icons" []: nothing -> nothing {
    let root = mktemp --directory
    let projects = [$root $root path join other]
    let file = $root | path join .nsm.nuon

    write-text $file ({
        projects: $projects
        icons: {directory: 'D'}
    } | to nuon)

    with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
        let config = get-config

        assert equal $config.projects $projects
        assert equal $config.icons.directory 'D'
        assert equal $config.icons.running '🟢'
    }

    remove-path $root
}

# Verify that the configured icons show up in the picker labels.
def "test custom-icons-in-labels" []: nothing -> nothing {
    in-store {|root|
        let config_dir = $root | path join .config
        make-dir $config_dir
        write-text ($config_dir | path join .nsm.nuon) ({icons: {stored: 'S'}} | to nuon)
        save-session demo $root

        with-env {XDG_CONFIG_HOME: $config_dir} {
            let label = list-candidates --sessions | get label | first

            assert ($label | str starts-with 'S') $'expected the custom icon in: ($label)'
        }
    }
}

# Verify that a malformed configuration file fails with its path.
def "test get-config-rejects-a-malformed-file" []: nothing -> nothing {
    let root = mktemp --directory

    write-text ($root | path join .nsm.nuon) 'not a record'

    with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
        let message = error-message { get-config }
        let has_path = match $message {
            null => false
            $text => ($text =~ '.nsm.nuon')
        }

        assert $has_path $'expected the file path in: ($message)'
    }

    remove-path $root
}

# Verify that restore arguments appear only when the file is configured and exists.
def "test get-restore-args" []: nothing -> nothing {
    let root = mktemp --directory
    let project = $root | path join project
    let file = $project | path join Session.vim
    make-dir $project
    make-file $file

    with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
        assert equal (get-restore-args $project) [] 'no configuration'

        write-text ($root | path join .nsm.nuon) ({restore: {file: 'Session.vim'}} | to nuon)
        assert equal (get-restore-args $project) ['-S' $file] 'configured file'

        write-text ($root | path join .nsm.nuon) ({restore: {file: 'Missing.vim'}} | to nuon)
        assert equal (get-restore-args $project) [] 'missing file'
    }

    remove-path $root
}

# Verify that every local commit message passes the Commitizen check.
def "test commit-messages-follow-conventional-commits" []: nothing -> nothing {
    for hash in (git log --format=%H | lines) {
        let file = mktemp
        write-text $file (git log -1 --format=%B $hash | str trim)

        let result = cz check --commit-msg-file $file | complete

        assert equal $result.exit_code 0 $'($hash): ($result.stderr)'
        remove-path $file
    }

    let bad = cz check -m 'add stuff' | complete

    assert ($bad.exit_code != 0) 'a non-conventional message must fail'
}

# Verify that a failing command prints its message without a source frame.
def "test errors-print-without-a-source-frame" []: nothing -> nothing {
    in-store {|root|
        let result = nu --no-config-file cli/main.nu attach /nope | complete

        assert ($result.exit_code != 0) 'the command must fail'
        assert (($result.stderr =~ 'No session is named /nope')) $result.stderr
        assert (($result.stderr =~ '\[E\]')) $'expected an error icon in: ($result.stderr)'
        assert (not ($result.stderr =~ '╭─')) $'unexpected source frame in: ($result.stderr)'
    }
}
