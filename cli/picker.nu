use lib.nu [fail]
use server.nu [is-alive]
use store.nu [get-display-path get-socket list-recent-sessions]

# Return the directories that zoxide knows.
def list-zoxide []: nothing -> list<string> {
    if (which zoxide | is-empty) {
        fail 'The picker needs zoxide to list directories. Install zoxide to use the picker.'
    }

    zoxide query --list | lines
}

# Return the rows of the picker: the sessions, then the zoxide directories and the projects that have no session yet.
def list-candidates [--exclude: string = '', --sessions]: nothing -> table {
    let known = list-recent-sessions
    | where name != $exclude
    | insert source {|session| if (is-alive $session.socket) { 'running' } else { 'stored' } }
    | insert label {|session| $"($session.source | fill --width 8) ($session.name)  (get-display-path $session.path)" }
    | select label name path source

    if $sessions {
        return $known
    }

    let directories = list-zoxide
    | append (list-projects)
    | uniq
    | where { ($in | path exists) and $in not-in $known.path }
    | wrap path
    | insert name null
    | insert source 'directory'
    | insert label {|row| $"($row.source | fill --width 8) (get-display-path $row.path)" }
    | select label name path source

    $known | append $directories
}

# Return the names of the buffers of a running server, one on each line.
def get-buffers [name: string]: nothing -> string {
    let result = nvim --server (get-socket $name) --remote-expr "v:lua.require'nsm'.buffers()" | complete

    if $result.exit_code != 0 {
        return 'The nsm plugin is not loaded in this server.'
    }

    $result.stdout
}

# Return the text that the picker shows for a row: the directory, the buffers of a running server, or the files.
def get-preview [candidate: record]: nothing -> string {
    if not ($candidate.path | path exists) {
        return [$candidate.path '' 'The directory does not exist.'] | str join (char nl)
    }

    let body = if $candidate.source == 'running' {
        get-buffers $candidate.name
    } else {
        try {
            ls --short-names $candidate.path
            | get name
            | first 30
            | str join (char nl)
        } catch {|err|
            fail $'Cannot list ($candidate.path): ($err.msg)'
        }
    }

    [$candidate.path $candidate.source '' $body] | str join (char nl)
}

# Ask for a row with skim. Return its session name, or its directory when it has no session yet, or nothing on cancel.
export def pick-candidate [--exclude: string = '', --sessions]: nothing -> oneof<string, nothing> {
    if (which sk | is-empty) {
        fail 'The picker needs the skim plugin. Install nu_plugin_skim, then run `plugin add nu_plugin_skim` and `plugin use nu_plugin_skim`.'
    }

    let candidates = list-candidates --exclude $exclude --sessions=$sessions

    if ($candidates | is-empty) {
        fail 'There is nothing to pick. Start a session with `nsm new <name>`.'
    }

    let preview = { get-preview $in }
    let picked = $candidates | sk --format {get label} --preview $preview --reverse --prompt 'nsm> '

    if $picked == null {
        return null
    }

    $picked.name | default $picked.path
}

# Return the git repositories under the projects directory.
export def list-projects []: nothing -> list<string> {
    let root = $env.PROJECTS_DIR?

    if ($root | is-empty) or not ($root | path exists) {
        return []
    }

    glob --depth 4 $"($root)/**/.git" | path dirname
}
