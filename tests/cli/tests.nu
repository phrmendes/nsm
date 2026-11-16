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
use ../../cli/picker.nu [get-preview list-candidates list-projects]
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
    get-socket
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
            socket: (get-socket work)
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
        let first = query-store ($root | path join nsm sessions.db) 'select * from sessions' | first
        query-store ($root | path join nsm sessions.db) 'update sessions set attached_at = 123 where name = :name' --params {name: work} | ignore
        save-session work $second_path
        let updated = query-store ($root | path join nsm sessions.db) 'select * from sessions' | first

        assert equal $updated.path $second_path 'updated project path'
        assert equal $updated.socket (get-socket work) 'stable socket path'
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

# Verify that project discovery finds repositories at depth four, under hidden parents, and with a `.git` file.
def "test list-projects-discovers-repositories-up-to-depth-four" []: nothing -> nothing {
    let root = mktemp --directory
    let directories = [
        repo1
        repo2/sub
        .hidden/repo3
        a/b/c
        a/b/c/d
        plain
        wt
    ]

    for directory in $directories {
        make-dir ($root | path join $directory)
    }

    for directory in [repo1 repo2/sub .hidden/repo3 a/b/c a/b/c/d] {
        make-dir ($root | path join $directory .git)
    }
    make-file ($root | path join wt .git)

    let expected = [repo1 repo2/sub .hidden/repo3 a/b/c wt]
    | each {|directory| $root | path join $directory }

    with-env {PROJECTS_DIR: $root} {
        assert equal (list-projects | sort) ($expected | sort) 'repositories at depth four'
    }
    with-env {PROJECTS_DIR: ($root | path join missing)} {
        assert equal (list-projects) [] 'missing projects directory'
    }
    with-env {PROJECTS_DIR: null} {
        assert equal (list-projects) [] 'unset projects directory'
    }

    remove-path $root
}

# Verify that connecting focuses an existing kitty tab and starts no new tab.
def "test connect-session-focuses-existing-kitty-tab" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let project = $root | path join project
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $project
    make-shim ($bin | path join kitten) --interpreter $bash
    make-shim ($bin | path join nvim) --interpreter $bash

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
        KITTY_LISTEN_ON: 'unix:/tmp/kitty'
        SHIM_FOCUS_EXIT: '0'
    } {
        create-store
        save-session demo $project
        make-file (get-socket demo)
        connect-session demo
    }

    let calls = open $log | lines
    assert (($calls | where $it =~ 'focus-tab' | length) == 1) 'one focus call'
    assert (($calls | where $it =~ 'launch' | length) == 0) 'no launch call'
    assert (($calls | where $it =~ 'setenv' | length) == 1) 'kitty env is forwarded'

    remove-path $root
}

# Verify that connecting opens a kitty tab with the session name, project directory, and env.
def "test connect-session-opens-kitty-tab-when-missing" []: nothing -> nothing {
    let root = mktemp --directory
    let bin = $root | path join bin
    let log = $root | path join calls.log
    let project = $root | path join project
    let path = [$bin] | append $env.PATH | str join (char esep)
    let bash = which bash | get --optional 0.path | default '/usr/bin/env bash'
    make-dir $bin
    make-dir $project
    make-shim ($bin | path join kitten) --interpreter $bash
    make-shim ($bin | path join nvim) --interpreter $bash

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
        KITTY_LISTEN_ON: 'unix:/tmp/kitty'
        SHIM_FOCUS_EXIT: '1'
    } {
        create-store
        save-session demo $project
        make-file (get-socket demo)
        connect-session demo
    }

    let launch = open $log | lines | where $it =~ 'launch' | first
    assert ($launch =~ '--type=tab') 'a tab is launched'
    assert ($launch =~ '--tab-title demo') 'the tab carries the session name'
    assert ($launch =~ $'--cwd ($project)') 'the tab opens in the project'
    assert ($launch =~ 'NSM_SESSION=demo') 'the tab carries the session env'
    assert ($launch =~ '--remote-ui') 'the tab attaches a UI'

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
        let socket = (get-socket demo)

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
    make-shim ($bin | path join kitten) --interpreter $bash
    make-shim ($bin | path join nvim) --interpreter $bash

    with-env {
        XDG_STATE_HOME: $root
        HOME: $root
        PATH: $path
        SHIM_LOG: $log
        KITTY_LISTEN_ON: 'unix:/tmp/kitty'
        SHIM_FOCUS_EXIT: '0'
    } {
        create-store
        make-file (get-socket project)

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
        assert (not ((get-socket one) | path exists)) 'socket is removed'

        let empty = nu --no-config-file cli/main.nu kill --all | complete
        assert equal $empty.exit_code 0 $empty.stderr
        assert (($empty.stdout =~ 'No sessions.')) $empty.stdout
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

# Verify that a missing configuration file gives the defaults.
def "test get-config-defaults-without-a-file" []: nothing -> nothing {
    let root = mktemp --directory

    with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
        let config = get-config

        assert equal $config.projects.dir null
        assert equal $config.icons.running '🟢'
        assert equal $config.icons.stored '⚫'
        assert equal $config.icons.directory '📁'
        assert equal $config.restore.file null
    }

    remove-path $root
}

# Verify that the file sets the projects folder and overrides single icons.
def "test get-config-reads-projects-and-icons" []: nothing -> nothing {
    let root = mktemp --directory
    let projects = $root | path join projects
    let file = $root | path join .nsm.nuon

    write-text $file ({
        projects: {dir: $projects}
        icons: {directory: 'D'}
    } | to nuon)

    with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
        let config = get-config

        assert equal $config.projects.dir $projects
        assert equal $config.icons.directory 'D'
        assert equal $config.icons.running '🟢'
    }

    remove-path $root
}

# Verify that projects.dir is used when PROJECTS_DIR is empty, and that PROJECTS_DIR wins when set.
def "test projects-dir-config-and-precedence" []: nothing -> nothing {
    let root = mktemp --directory
    let projects = $root | path join projects
    let repository = $projects | path join repo
    let other = $root | path join other
    make-dir ($repository | path join .git)
    make-dir ($other | path join .git)

    write-text ($root | path join .nsm.nuon) ({
        projects: {dir: $projects}
    } | to nuon)

    with-env {XDG_CONFIG_HOME: $root, HOME: $root, PROJECTS_DIR: ''} {
        assert equal (list-projects) [$repository] 'config directory'
    }
    with-env {XDG_CONFIG_HOME: $root, HOME: $root, PROJECTS_DIR: $other} {
        assert equal (list-projects) [$other] 'environment wins'
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
