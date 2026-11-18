use std/assert
use ./fixtures.nu [read-file run-tests]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

def "test readme-and-help-name-every-command" []: nothing -> nothing {
    let commands = nu --no-config-file cli/main.nu
    | lines
    | each {|line| $line | str trim | split row ' ' | first }

    assert (($commands | length) > 0) 'the help lists the commands'

    for file in [README.md doc/nsm.txt] {
        let text = read-file $file

        for command in $commands {
            assert ($text | str contains $'nsm ($command)') $'($file) does not name `nsm ($command)`'
        }
    }
}
