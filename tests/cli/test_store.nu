use std/assert
use ./fixtures.nu [
    in-store
    make-dir
    query-store
    run-tests
]
use ../../cli/store.nu [create-store get-previous-session-name save-session]
use ../../cli/target.nu [resolve-target]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

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
}

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

def "test create-store-migrates-only-legacy-attachment-times" []: nothing -> nothing {
    let cases = [
        [name, version, attached, expected];
        ['a legacy timestamp moves to nanoseconds', 0, 1700000000, 1_700_000_000_000_000_000]
        ['a legacy null stays null', 0, null, null]
        ['a current version stays unchanged', 1, 1700000000, 1700000000]
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
            assert equal $version.user_version 1 'the schema version is recorded'
        }
    }
}
