use std/assert
use ./fixtures.nu [
    error-message
    run-tests
    write-text
]
use ../../cli/lib.nu [EXIT_UNSAVED fail get-display-path get-project-path]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Verify that fail raises a catchable error with its message.
def "test fail-stays-catchable" []: nothing -> nothing {
    assert equal (error-message { fail 'boom' }) 'boom'
    assert equal (error-message { fail 'boom' --code $EXIT_UNSAVED }) 'boom'
}

# Verify that report-error exits with the code that the error carries.
def "test report-error-exits-with-the-carried-code" []: nothing -> nothing {
    let cases = [
        [name, command, expected];
        ['the default code', "fail 'boom'", 1]
        ['an unsaved-changes code', $'fail "boom" --code ($EXIT_UNSAVED)', 3]
        ['a custom code', "fail 'boom' --code 7", 7]
        ['an error without a code', 'open /nonexistent/file.txt | ignore', 1]
    ]

    let lib = $env.CURRENT_FILE | path dirname | path join ../../cli/lib.nu | path expand
    let use_lib = 'use ' + ($lib | to nuon) + ' [report-error fail EXIT_UNSAVED]'

    for case in $cases {
        let script = (
            [
                $use_lib
                $"def main [] { report-error { ($case.command) } }"
                'main'
            ] | str join (char nl)
        )
        let file = mktemp
        write-text $file $script
        let result = nu --no-config-file $file | complete

        assert equal $result.exit_code $case.expected $case.name
        assert (($result.stderr | ansi strip | str contains '[E]')) $'($case.name): ($result.stderr)'
    }
}

# Verify home abbreviation at path boundaries and preserve unrelated paths.
def "test get-display-path-abbreviates-only-home-descendants" []: nothing -> nothing {
    let cases = [
        [name, path, expected];
        ['home itself', /home/ana, '~']
        ['child of home', /home/ana/project, '~/project']
        ['deep child of home', /home/ana/project/src, '~/project/src']
        ['sibling shares the home prefix', /home/anabel/project, /home/anabel/project]
        ['home text occurs later', /srv/home/ana/project, /srv/home/ana/project]
        ['unrelated path', /srv/project, /srv/project]
    ]

    with-env {HOME: /home/ana} {
        for case in $cases {
            assert equal (get-display-path $case.path) $case.expected $case.name
        }
    }

    with-env {HOME: '/home/ana/'} {
        assert equal (get-display-path /home/ana/project) '~/project' 'a trailing slash in HOME'
        assert equal (get-display-path /home/ana) '~' 'home itself with a trailing slash'
    }
}

# Verify that a path under a project root loses the longest matching root.
def "test get-project-path-strips-the-longest-project-root" []: nothing -> nothing {
    let cases = [
        [name, path, roots, expected];
        ['under a root', /p/neovim/nsm, [/p], neovim/nsm]
        ['deep under a root', /p/a/b/c, [/p], a/b/c]
        ['the root itself', /p, [/p], /p]
        ['a sibling shares the prefix', /p-old/neovim, [/p], /p-old/neovim]
        ['outside every root', /srv/app, [/p], /srv/app]
        ['two nested roots keep the longest', /p/a/b/c, [/p /p/a], b/c]
        ['no roots', /p/neovim, [], /p/neovim]
    ]

    for case in $cases {
        assert equal (get-project-path $case.path $case.roots) $case.expected $case.name
    }

    with-env {HOME: /home/ana} {
        assert equal (get-project-path /home/ana/notes [/p]) '~/notes' 'home still abbreviates'
    }
}
