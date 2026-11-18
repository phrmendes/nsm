use std/assert
use ./fixtures.nu [
    in-root
    run-tests
    write-text
]
use ../../cli/config.nu [get-config]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

def "test get-config-defaults-without-a-file" []: nothing -> nothing {
    in-root {|root|
        with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
            assert equal (get-config) {
                projects: []
                icons: {
                    running: '🟢'
                    stored: '⚫'
                    directory: '📁'
                }
                restore: {file: null}
                start: {environment: true, timeout: 300}
            }
        }
    }
}

def "test get-config-merges-the-start-keys" []: nothing -> nothing {
    in-root {|root|
        write-text ($root | path join .nsm.nuon) ({start: {timeout: 30}} | to nuon)

        with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
            assert equal (get-config).start {environment: true, timeout: 30}
        }
    }
}
