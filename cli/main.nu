use completions.nu [get-completions]
use lib.nu [EXIT_UNSAVED fail report-error warn]
use picker.nu [list-candidates pick-candidate]
use render.nu [format-sessions format-sessions-json]
use server.nu [
    connect-session
    get-dirty-sessions
    has-unsaved-changes
    is-alive
    start-session
    stop-session
]
use names.nu [check-name]
use store.nu [
    create-store
    find-session
    get-previous-session-name
    get-session
    list-session-names
    list-sessions
    save-session
    touch-session
]
use version.nu [VERSION]

$env.config = ($env.config | upsert error_style 'short')

# Run a closure against the session store, and report its failure.
def run-command [body: closure]: nothing -> nothing {
    report-error {
        create-store
        do $body
    }
}

# Stop every session, and refuse sessions with unsaved changes unless `force` is set.
def kill-all [force: bool]: nothing -> nothing {
    let sessions = list-sessions

    if ($sessions | is-empty) {
        warn 'No sessions.'
        return
    }

    if not $force {
        let dirty = get-dirty-sessions $sessions

        if ($dirty | is-not-empty) {
            fail $'These sessions have unsaved changes: ($dirty | str join ", "). Save them, or run `nsm kill --all --force`.' --code $EXIT_UNSAVED
        }
    }

    for session in $sessions {
        stop-session $session.name --force=$force
    }
}

# Stop one session, and refuse it with unsaved changes unless `force` is set.
def kill-one [target: string, force: bool]: nothing -> nothing {
    let session = get-session $target

    if not $force and (is-alive $session.socket) and (has-unsaved-changes $target) {
        fail $'The session ($target) has unsaved changes. Save them, or run `nsm kill --force ($target)`.' --code $EXIT_UNSAVED
    }

    stop-session $target --force=$force
}

# Return the `main` commands of this file with their short forms and parameters.
def get-commands []: nothing -> table<name: string, short: oneof<string, nothing>, summary: string, parameters: list<record<name: string, kind: string, shape: oneof<string, nothing>, short: oneof<string, nothing>, optional: bool>>> {
    let aliases = scope aliases | where {|alias| $alias.name starts-with 'main ' }

    scope commands
    | where {|command| $command.name starts-with 'main ' }
    | each {|command|
        let short = $aliases | where expansion == $command.name | get --optional 0.name

        {
            name: ($command.name | str replace 'main ' '')
            short: ($short | if $in == null { null } else { str replace 'main ' '' })
            summary: ($command.description | str replace --regex '\.$' '')
            parameters: (
                $command.signatures
                | values
                | first
                | where parameter_type in [positional named switch]
                | each {|parameter|
                    {
                        name: $parameter.parameter_name
                        kind: $parameter.parameter_type
                        shape: $parameter.syntax_shape
                        short: $parameter.short_flag
                        optional: $parameter.is_optional
                    }
                }
            )
        }
    }
}

# Pick another session and open it.
#
# The picker does not list the current session.
def "main switch" [
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    run-command {
        let current = $env.NSM_SESSION?
        let chosen = if $current == null {
            pick-candidate --scope $scope
        } else {
            pick-candidate --exclude $current --scope $scope
        }

        connect-session $chosen
    }
}

# Return to the session that you opened before the current one.
def "main last" [
    --print # Print the socket of the session and do not open it
]: nothing -> nothing {
    run-command {
        let previous = get-previous-session-name

        if $previous == null {
            fail 'There is no previous session.'
        }

        if not $print {
            connect-session $previous
            return
        }

        let session = start-session $previous

        touch-session $session.name
        print $session.socket
    }
}

# Create or attach to a session.
#
# The target is a session name or a directory. Without a target, pick one.
def "main attach" [
    target?: string # A session name or a directory
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    run-command {
        connect-session ($target | default {|| pick-candidate --scope $scope })
    }
}

# Create a named session for a directory, and open it.
def "main new" [
    name: string # The name of the session
    path?: path # The directory of the project, the current directory by default
]: nothing -> nothing {
    run-command {
        check-name $name

        let directory = $path | default $env.PWD | path expand

        if ($directory | path type) != 'dir' {
            fail $'($directory) is not a directory.'
        }

        let existing = find-session $name

        if $existing != null and (is-alive $existing.socket) {
            fail $'The session ($name) is already running.'
        }

        save-session $name $directory | ignore
        connect-session $name
    }
}

# Print the sessions in a table.
#
# The table shows the name, the status, the path, and the time of the last attach.
# The status is `active` or `inactive`.
def "main list" [
    --json # Print the sessions as JSON
]: nothing -> nothing {
    run-command {
        let sessions = list-sessions
        | insert active {|session| is-alive $session.socket }

        if $json {
            print (format-sessions-json $sessions)
            return
        }

        print (format-sessions $sessions)
    }
}

# Print the rows of the picker as JSON for the Neovim plugin.
def "main pick" [
    --sessions # Only list sessions, not directories
    --scope: string = '' # Only list rows under this directory
]: nothing -> nothing {
    run-command {
        let exclude = $env.NSM_SESSION? | default {|| ''}
        let rows = list-candidates --exclude $exclude --sessions=$sessions --scope $scope

        $rows | to json
    }
}

# Start the server of a session and print its socket.
#
# The session counts as attached.
def "main start" [
    target: string # A session name or a directory
]: nothing -> nothing {
    run-command {
        let session = start-session $target

        touch-session $session.name
        print $session.socket
    }
}

# Stop the server of a session and forget the session.
#
# Without a name, pick one of the sessions.
# The command refuses a session with unsaved changes, and a server that does not answer.
# Use `--force` to stop it anyway.
def "main kill" [
    name?: string # The session to stop
    --all (-a) # Stop every session
    --force (-f) # Stop a session even when it has unsaved changes or does not answer
    --scope: string = '' # Only pick sessions under this directory
]: nothing -> nothing {
    run-command {
        if $all {
            kill-all $force
            return
        }

        let target = $name | default {|| pick-candidate --sessions --scope $scope }

        if $target != null {
            kill-one $target $force
        }
    }
}

# Print the session names, one per line.
def "main names" []: nothing -> nothing {
    run-command {
        for name in (list-session-names) {
            print $name
        }
    }
}

# Print the script that completes nsm in a shell.
#
# The shell is `bash`, `zsh`, or `nu`.
def "main completions" [
    shell: string # The shell to complete for
]: nothing -> nothing {
    report-error {
        print (get-completions $shell (get-commands))
    }
}

# Print the subcommands of nsm, or the version with `--version`.
def main [
    --version (-v) # Print the version
]: nothing -> nothing {
    if $version {
        print $'nsm ($VERSION)'
        return
    }

    get-commands
    | each {|command| $"  ($command.name)  ($command.summary)" }
    | str join (char nl)
    | print
}

# Pick another session and open it.
alias "main s" = main switch

# Return to the previous session.
alias "main l" = main last

# Create or attach to a session.
alias "main a" = main attach

# Create a named session.
alias "main n" = main new

# Print sessions as a table.
alias "main ls" = main list

# Stop a session.
alias "main k" = main kill
