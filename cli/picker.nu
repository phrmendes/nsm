use config.nu [get-config]
use lib.nu [fail get-display-path warn]
use server.nu [is-alive]
use ssh.nu [list-ssh-hosts]
use store.nu [list-recent-sessions]

const ZOXIDE_LIMIT = 5
const PREVIEW_LIMIT = 30
const PROJECT_DEPTH = 4

# Return the icon of a row, falling back to the directory icon.
def get-icon [source: string, icons: record]: nothing -> string {
    $icons | get --optional $source | default $icons.directory
}

# Return the label of a row: the icon, the session name when it has one, and the path.
def get-label [row: record, icons: record]: nothing -> string {
    let icon = get-icon $row.source $icons
    let path = get-display-path $row.path
    let prefix = if $row.source == 'zoxide' { '[Z] ' } else { '' }

    if ($row.name | is-empty) {
        return $"($prefix)($icon) ($path)"
    }

    $"($prefix)($icon) ($row.name)  ($path)"
}

# Return the resolved scope: the argument, then `NSM_SCOPE`, then nothing.
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

# Return the directories that zoxide knows.
def list-zoxide []: nothing -> list<string> {
    if (which zoxide | is-empty) {
        warn 'zoxide is not installed; recent directories are hidden.'
        return []
    }

    zoxide query --list | lines | first $ZOXIDE_LIMIT
}

# Return whether a path is inside the scope. An empty scope keeps every path.
def in-scope [path: string, scope: string]: nothing -> bool {
    if ($scope | is-empty) {
        return true
    }

    let target = $path | path expand

    $target == $scope or ($target | str starts-with $"($scope)/")
}

# Return the text that the picker shows for a row: the path and the files in it.
export def get-preview [candidate: record]: nothing -> string {
    if not ($candidate.path | path exists) {
        return (
            [$candidate.path '' 'The directory does not exist.']
            | str join (char nl)
        )
    }

    let body = try {
        ls --short-names $candidate.path
        | get name
        | first $PREVIEW_LIMIT
        | str join (char nl)
    } catch {|err|
        fail $'Cannot list ($candidate.path): ($err.msg)'
    }

    [$candidate.path 'Files' '' $body] | str join (char nl)
}

# Pick a row with fzf. Return its session name, its directory, or nothing on cancel.
export def pick-candidate [--exclude: string = '', --sessions, --scope: string = '']: nothing -> oneof<string, nothing> {
    if (which fzf | is-empty) {
        fail 'The picker needs fzf. Install fzf and put it on PATH.'
    }

    let candidates = list-candidates --exclude $exclude --sessions=$sessions --scope $scope

    if ($candidates | is-empty) {
        fail 'There is nothing to pick. Start a session with `nsm new <name>`.'
    }

    let format = {|candidate|
        let label = $candidate.label | str replace --all --regex '[\t\n]' ' '
        [
            $label
            ($candidate | to json --raw | encode base64)
        ] | str join (char tab)
    }
    let input = $candidates | each $format | str join (char nl)
    let result = $input
    | fzf --delimiter '\t' --with-nth '1' --preview 'nsm preview {2}' --layout reverse --height '50%' --prompt 'nsm> '
    | complete

    if $result.exit_code != 0 {
        return null
    }

    let picked = $result.stdout | str trim | split row (char tab) | get --optional 1

    if $picked == null {
        return null
    }

    let row = try {
        $picked | decode base64 | decode | from json
    } catch {
        fail 'The picker returned invalid data.'
    }

    $row.name | default $row.path
}

# Return the git repositories under the configured project roots.
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

# Return the rows for the SSH hosts in the user's configuration.
export def list-host-candidates []: nothing -> table {
    let icons = (get-config).icons

    list-ssh-hosts
    | each {|host| {
        label: $"($icons.host) ($host)"
        name: null
        path: null
        source: 'host'
        address: $"ssh://($host)"
    }}
}

# Return the picker rows of the sessions, without the excluded name.
export def list-session-rows [exclude: string, icons: record]: nothing -> table {
    list-recent-sessions
    | where name != $exclude
    | par-each {|session| $session | insert alive (is-alive $session.socket) }
    | insert source {|session| if $session.alive { 'running' } else { 'stored' } }
    | insert label {|session| get-label $session $icons }
    | select label name path source
}

# Return the picker rows of the directories that are not sessions.
def make-directory-rows [paths: list<string>, options: record]: nothing -> table {
    $paths
    | uniq
    | wrap path
    | insert name null
    | insert source $options.source
    | insert label {|row| get-label $row $options.icons }
    | select label name path source
}

# Return the rows of the picker: sessions, configured projects, and zoxide directories.
export def list-candidates [--exclude: string = '', --sessions, --scope: string = '']: nothing -> table {
    let icons = (get-config).icons
    let scope = get-scope $scope

    let known = list-session-rows $exclude $icons

    if $sessions {
        return ($known | where {|row| in-scope $row.path $scope })
    }

    let projects = list-projects
    | where { ($in | path exists) and $in not-in $known.path }

    let zoxide = list-zoxide
    | where { ($in | path exists) and $in not-in $known.path and $in not-in $projects }

    $known
    | append (make-directory-rows $projects {source: 'directory', icons: $icons})
    | append (make-directory-rows $zoxide {source: 'zoxide', icons: $icons})
    | where {|row| in-scope $row.path $scope }
}
