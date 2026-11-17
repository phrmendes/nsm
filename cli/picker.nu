use config.nu [get-config]
use lib.nu [fail get-project-path warn]
use server.nu [get-state]
use store.nu [list-recent-sessions]

const ZOXIDE_LIMIT = 5
# The shell command that previews the directory in the second field of a row.
export const PREVIEW = 'if [ -d {2} ]; then printf "%s\\n\\nFiles\\n\\n" {2}; ls -1 {2} | head -30; else printf "%s\\n\\nThe directory does not exist.\\n" {2}; fi'
const PROJECT_DEPTH = 4

def get-icon [source: string, icons: record]: nothing -> string {
    $icons | get --optional $source | default $icons.directory
}

def get-label [row: record, options: record]: nothing -> string {
    let icon = get-icon $row.source $options.icons
    let path = get-project-path $row.path $options.roots
    let suffix = if $row.source == 'zoxide' { ' [Z]' } else { '' }

    if ($row.name | is-empty) {
        return $"($icon) ($path)($suffix)"
    }

    $"($icon) ($row.name)  ($path)($suffix)"
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

def list-zoxide []: nothing -> list<string> {
    if (which zoxide | is-empty) {
        warn 'zoxide is not installed. Recent directories are hidden.'
        return []
    }

    zoxide query --list | lines
}

# Return whether a path is inside the scope. An empty scope keeps every path.
def in-scope [path: string, scope: string]: nothing -> bool {
    if ($scope | is-empty) {
        return true
    }

    let target = $path | path expand
    let scope = $scope | path expand

    $target == $scope or ($target | str starts-with $"($scope)/")
}

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
            $candidate.path
            ($candidate.name | default '')
        ] | str join (char tab)
    }
    let input = $candidates | each $format | str join (char nl)
    let result = $input
    | fzf --delimiter '\t' --with-nth '1' --preview $PREVIEW --layout reverse --height '50%' --prompt 'nsm> '
    | complete

    if $result.exit_code != 0 {
        return null
    }

    let picked = $result.stdout | lines | get --optional 0

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

def list-session-rows [exclude: string, options: record]: nothing -> table {
    list-recent-sessions
    | where name != $exclude
    | par-each {|session| $session | insert state (get-state $session.socket) }
    | insert source {|session| if $session.state == 'stopped' { 'stored' } else { $session.state } }
    | insert label {|session| get-label $session $options }
    | select label name path source
}

def make-directory-rows [paths: list<string>, source: string, options: record]: nothing -> table {
    $paths
    | uniq
    | wrap path
    | insert name null
    | insert source $source
    | insert label {|row| get-label $row $options }
    | select label name path source
}

# Return the rows of the picker: sessions, configured projects, and zoxide directories.
export def list-candidates [--exclude: string = '', --sessions, --scope: string = '']: nothing -> table {
    let config = (get-config)
    let options = {icons: $config.icons, roots: $config.projects}
    let scope = get-scope $scope

    let known = list-session-rows $exclude $options

    if $sessions {
        return ($known | where {|row| in-scope $row.path $scope })
    }

    let roots = $config.projects | each {|root| $root | path expand }

    let projects = list-projects
    | where { ($in | path exists) and $in not-in $known.path }

    let zoxide = list-zoxide
    | where {|path|
        ($path | path exists) and $path not-in $known.path and (not ($roots | any {|root| in-scope $path $root }))
    }
    | first $ZOXIDE_LIMIT

    $known
    | append (make-directory-rows $projects 'directory' $options)
    | append (make-directory-rows $zoxide 'zoxide' $options)
    | where {|row| in-scope $row.path $scope }
}
