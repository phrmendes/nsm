use std/assert
use ./fixtures.nu [
    error-message
    in-root
    make-dir
    run-tests
]
use ../../cli/names.nu [check-name get-free-name get-session-name]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

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

def "test get-session-name-uses-git-root-for-all-descendants" []: nothing -> nothing {
    in-root {|root|
        let repository = $root | path join 'my repo'
        let outside = $root | path join 'my project!'
        let paths = [
            $repository
            ($repository | path join src)
            ($repository | path join src nested)
        ]

        for path in $paths {
            make-dir $path
        }
        make-dir $outside
        git init --quiet $repository

        for path in $paths {
            assert equal (get-session-name $path) 'my-repo' $path
        }

        assert equal (get-session-name $outside) 'my-project-' 'outside a repository the basename is sanitized'

        let without_git = with-env {PATH: []} { get-session-name ($repository | path join src) }
        assert equal $without_git 'src' 'without git the basename is used'
    }
}
