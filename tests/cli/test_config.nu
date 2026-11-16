use std/assert
use ./fixtures.nu [
    in-root
    run-tests
]
use ../../cli/config.nu [get-config]

def main []: nothing -> nothing { run-tests $env.CURRENT_FILE }

# Verify that a missing configuration file gives the exact defaults.
def "test get-config-defaults-without-a-file" []: nothing -> nothing {
    in-root {|root|
        with-env {XDG_CONFIG_HOME: $root, HOME: $root} {
            assert equal (get-config) {
                projects: []
                icons: {
                    running: '🟢'
                    busy: '🟡'
                    stored: '⚫'
                    directory: '📁'
                }
                restore: {file: null}
            }
        }
    }
}
