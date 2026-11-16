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

    if ($row.name | is-empty) {
        return $"($icon) ($path)"
    }

    $"($icon) ($row.name)  ($path)"
}

# Return the directories that zoxide knows.
def list-zoxide []: nothing -> list<string> {
    if (which zoxide | is-empty) {
        fail 'The picker needs zoxide to list directories. Install zoxide to use the picker.'
    }

    zoxide query --list | lines
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

# Ask for a row with skim. Return its session name, or its directory when it has no session yet, or nothing on cancel.
export def pick-candidate [--exclude: string = '', --sessions, --scope: string = '']: nothing -> oneof<string, nothing> {
    if (which sk | is-empty) {
        fail 'The picker needs the skim plugin. Install nu_plugin_skim, then run `plugin add nu_plugin_skim` and `plugin use nu_plugin_skim`.'
    }

    let candidates = list-candidates --exclude $exclude --sessions=$sessions --scope $scope

    if ($candidates | is-empty) {
        fail 'There is nothing to pick. Start a session with `nsm new <name>`.'
    }

    let preview = { get-preview $in }
    let picked = $candidates | sk --format {get label} --preview $preview --reverse --height '50%' --prompt 'nsm> '

    if $picked == null {
        return null
    }

    $picked.name | default $picked.path
}

# Return the git repositories under the projects directory.
export def list-projects []: nothing -> list<string> {
    let config = (get-config)
    let root = $env.PROJECTS_DIR?
    let root = if ($root | is-empty) { $config.projects.dir } else { $root }

    if ($root | is-empty) or not ($root | path exists) {
        return []
    }

    glob --depth 4 $"($root)/**/.git" | path dirname
}

# Return the rows of the picker: the sessions, then the zoxide directories and the projects that have no session yet.
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

    let directories = [
        {|| list-zoxide }
        {|| list-projects }
    ]
    | par-each {|job| do $job }
    | flatten
    | uniq
    | where { ($in | path exists) and $in not-in $known.path }
    | wrap path
    | insert name null
    | insert source 'directory'
    | insert label {|row| get-label $row $icons }
    | select label name path source

    $known | append $directories | where {|row| in-scope $row.path $scope }
}
