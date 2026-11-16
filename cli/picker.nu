use config.nu [get-config]
use lib.nu [fail]
use server.nu [is-alive]
use store.nu [get-display-path list-recent-sessions]

# Return the icon of a row.
def get-icon [source: string, icons: record]: nothing -> string {
    match $source {
        'running' => $icons.running
        'stored' => $icons.stored
        _ => $icons.directory
    }
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

# Return the directories that zoxide knows.
def list-zoxide []: nothing -> list<string> {
    if (which zoxide | is-empty) {
        fail 'The picker needs zoxide to list directories. Install zoxide to use the picker.'
    }

    zoxide query --list | lines | first 5
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
        return [$candidate.path '' 'The directory does not exist.'] | str join (char nl)
    }

    let body = try {
        ls --short-names $candidate.path
        | get name
        | first 30
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
        let label = $candidate.label | str replace --all (char tab) ' ' | str replace --all (char nl) ' '
        [
            $label
            ($candidate | to json --raw)
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

    let row = $picked | from json
    $row.name | default $row.path
}

# Return the git repositories under the configured project roots.
export def list-projects []: nothing -> list<string> {
    (get-config).projects
    | each {|root|
        let directory = $root | path expand

        if ($directory | path exists) {
            glob --depth 4 $"($directory)/**/.git" | path dirname
        } else {
            []
        }
    }
    | flatten
    | uniq
}

# Return the rows of the picker: sessions, configured projects, and zoxide directories.
export def list-candidates [--exclude: string = '', --sessions, --scope: string = '']: nothing -> table {
    let config = (get-config)
    let icons = $config.icons

    let scope = if ($scope | is-not-empty) {
        $scope
    } else {
        $env.NSM_SCOPE?
    }
    let scope = if ($scope | is-empty) {
        ''
    } else {
        $scope | path expand
    }

    let known = list-recent-sessions
    | where name != $exclude
    | par-each {|session| $session | insert alive (is-alive $session.socket) }
    | insert source {|session| if $session.alive { 'running' } else { 'stored' } }
    | insert label {|session| get-label $session $icons }
    | select label name path source

    if $sessions {
        return ($known | where {|row| in-scope $row.path $scope })
    }

    let projects = list-projects
    | uniq
    | where { ($in | path exists) and $in not-in $known.path }
    | wrap path
    | insert name null
    | insert source 'directory'
    | insert label {|row| get-label $row $icons }
    | select label name path source

    let zoxide = list-zoxide
    | uniq
    | where { ($in | path exists) and $in not-in $known.path and $in not-in $projects.path }
    | wrap path
    | insert name null
    | insert source 'zoxide'
    | insert label {|row| get-label $row $icons }
    | select label name path source

    $known | append $projects | append $zoxide | where {|row| in-scope $row.path $scope }
}
