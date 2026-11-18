use config.nu [get-config]
use lib.nu [fail get-project-path warn]
use server.nu [is-alive]
use store.nu [list-recent-sessions]

const PROJECT_DEPTH = 4
const ZOXIDE_LIMIT = 5

# The shell command that previews the directory in the second field of a row.
export const PREVIEW = 'if [ -d {2} ]; then printf "%s\\n" {2}; ls -1 {2} | head -30; else printf "%s\\n\\nThe directory does not exist.\\n" {2}; fi'

# Return the icon of a row source, or the directory icon.
def get-icon [source: string, icons: record<running: string, stored: string, directory: string>]: nothing -> string {
    $icons | get --optional $source | default $icons.directory
}

# Return the label of a row: its icon, its path, and the zoxide tag.
def get-label [row: record<path: string, source: string>, options: record<icons: record<running: string, stored: string, directory: string>, roots: list<string>>]: nothing -> string {
    let icon = get-icon $row.source $options.icons
    let path = get-project-path $row.path $options.roots
    let suffix = if $row.source == 'zoxide' { ' [Z]' } else { '' }

    $"($icon) ($path)($suffix)"
}

# Return the scope from the argument or from `NSM_SCOPE`, or an empty string.
def get-scope [scope: string]: nothing -> string {
    let scope = if ($scope | is-not-empty) {
        $scope
    } else {
        $env.NSM_SCOPE?
    }

    if ($scope | is-empty) {
        ''
    } else {
        $scope | path expand
    }
}

# Return the directories that zoxide knows, most used first.
def list-zoxide []: nothing -> list<string> {
    if (which zoxide | is-empty) {
        warn 'zoxide is missing. nsm hides the recent directories.'
        return []
    }

    zoxide query --list | lines
}

# Check whether a path is inside the scope. An empty scope keeps every path.
def in-scope [path: string, scope: string]: nothing -> bool {
    if ($scope | is-empty) {
        return true
    }

    let target = $path | path expand
    let scope = $scope | path expand

    $target == $scope or ($target | str starts-with $"($scope)/")
}

# Return the picker rows of the sessions, without the excluded name.
def list-session-rows [exclude: string, options: record<icons: record<running: string, stored: string, directory: string>, roots: list<string>>]: nothing -> table<label: string, name: oneof<string, nothing>, path: string, source: string> {
    list-recent-sessions
    | where name != $exclude
    | insert source {|session| if (is-alive $session.socket) { 'running' } else { 'stored' } }
    | insert label {|session| get-label $session $options }
    | select label name path source
}

# Return the picker rows of directories that are not sessions.
def make-directory-rows [paths: list<string>, source: string, options: record<icons: record<running: string, stored: string, directory: string>, roots: list<string>>]: nothing -> table<label: string, name: oneof<string, nothing>, path: string, source: string> {
    $paths
    | uniq
    | wrap path
    | insert name null
    | insert source $source
    | insert label {|row| get-label $row $options }
    | select label name path source
}

# Pick a row with fzf, and return its session name, its directory, or nothing on cancel.
export def pick-candidate [--exclude: string = '', --sessions, --scope: string = '']: nothing -> oneof<string, nothing> {
    if (which fzf | is-empty) {
        fail 'The picker needs fzf. Install fzf and put it on PATH.'
    }

    let format = {|candidate|
        let label = $candidate.label | str replace --all --regex '[\t\n]' ' '
        [
            $label
            $candidate.path
            ($candidate.name | default '')
        ] | str join (char tab)
    }
    let result = list-candidates --exclude $exclude --sessions=$sessions --scope $scope
    | each $format
    | to text
    | with-env {SHELL: /bin/sh} {
        fzf --delimiter '\t' --with-nth '1' --preview $PREVIEW --layout reverse --height '50%' --prompt 'nsm> ' --exit-0 --print-query
    }
    | complete
    let output = $result.stdout | lines

    # With an empty query every row matches, so exit code 1 means that there were no rows.
    if $result.exit_code == 1 and ($output | get --optional 0 | default '' | is-empty) {
        fail 'There is nothing to pick. Start a session with `nsm new <name>`.'
    }

    if $result.exit_code != 0 {
        return null
    }

    let picked = $output | get --optional 1

    if $picked == null {
        return null
    }

    let fields = $picked | split row (char tab)

    let name = $fields | get --optional 2 | default ''

    if ($name | is-empty) {
        $fields | get 1
    } else {
        $name
    }
}

# Return the git repositories below the configured project roots.
export def list-projects []: nothing -> list<string> {
    (get-config).projects
    | each {|root|
        let directory = $root | path expand

        if ($directory | path exists) {
            glob --depth $PROJECT_DEPTH $"($directory)/**/.git" | path dirname
        } else {
            []
        }
    }
    | flatten
    | uniq
}

# Return the picker rows as a stream, one source at a time.
export def list-candidates [--exclude: string = '', --sessions, --scope: string = '']: nothing -> table<label: string, name: oneof<string, nothing>, path: string, source: string> {
    let config = get-config
    let options = {icons: $config.icons, roots: $config.projects}
    let scope = get-scope $scope

    let known = list-session-rows $exclude $options

    if $sessions {
        return ($known | where {|row| in-scope $row.path $scope })
    }

    let roots = $config.projects | each {|root| $root | path expand }

    let sources = [
        {|| $known }
        {||
            list-projects
            | where { ($in | path exists) and $in not-in $known.path }
            | make-directory-rows $in 'directory' $options
        }
        {||
            list-zoxide
            | where {|path|
                ($path | path exists) and $path not-in $known.path and (not ($roots | any {|root| in-scope $path $root }))
            }
            | first $ZOXIDE_LIMIT
            | make-directory-rows $in 'zoxide' $options
        }
    ]

    $sources
    | each --flatten {|source| do $source }
    | where {|row| in-scope $row.path $scope }
}
