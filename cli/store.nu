use lib.nu [fail]

# Return the directory of the state of nsm.
def get-state-dir []: nothing -> string {
    $env.XDG_STATE_HOME? | default {|| $env.HOME | path join .local/state } | path join nsm
}

# Return the file of the database of the sessions.
def get-db-file []: nothing -> string {
    get-state-dir | path join sessions.db
}

# Run SQL against the database of the sessions. Name each parameter in the query as `:name`.
def run-sql [query: string, --params: record = {}]: nothing -> table {
    try {
        open (get-db-file) | query db $query --params $params
    } catch {|err|
        fail $'Cannot query the sessions: ($err.msg)'
    }
}

# Return the time in nanoseconds since the epoch.
def get-time []: nothing -> int {
    date now | into int
}

# Convert the attachment times of an older store from seconds to nanoseconds.
def migrate-store []: nothing -> nothing {
    let version = run-sql 'select user_version from pragma_user_version' | first | get user_version

    if $version < 1 {
        run-sql 'update sessions set attached_at = attached_at * 1000000000 where attached_at is not null'
        | ignore
        run-sql 'pragma user_version = 1' | ignore
    }
}

# Return the row of a session, or nothing when no session has that name.
def find-session [name: string]: nothing -> oneof<record, nothing> {
    run-sql 'select name, path, socket from sessions where name = :name' --params {name: $name}
    | get --optional 0
}

# Return the socket of a session.
export def get-socket [name: string]: nothing -> string {
    get-state-dir | path join $'($name).sock'
}

# Create the database and the table of the sessions when they are missing.
export def create-store []: nothing -> nothing {
    try {
        mkdir (get-state-dir)
    } catch {|err|
        fail $"Cannot create (get-state-dir): ($err.msg)"
    }

    if not (get-db-file | path exists) {
        [[seed]; [0]] | into sqlite (get-db-file) --table-name seed
        run-sql 'drop table seed' | ignore
    }

    run-sql 'create table if not exists sessions (
        name text primary key,
        path text not null,
        socket text not null,
        created_at integer not null,
        attached_at integer
    )' | ignore

    migrate-store
}

# Stop when the name is empty or has a character that is not safe in a file name.
export def check-name [name: string]: nothing -> nothing {
    if $name !~ '^[a-zA-Z0-9._-]+$' {
        fail 'A session name may only hold letters, digits, dots, dashes and underscores.'
    }
}

# Return the name that a directory gets as a session: the basename of its git root, or of the directory itself.
export def get-session-name [directory: path]: nothing -> string {
    let root = git -C $directory rev-parse --show-toplevel | complete
    let base = if $root.exit_code == 0 {
        $root.stdout | str trim
    } else {
        $directory
    }

    $base | path basename | str replace --all --regex '[^a-zA-Z0-9._-]' '-'
}

# Return the first of the base and its numbered variants that no session uses.
@example 'a free name stays as it is' { get-free-name app } --result app
@example 'a taken name gets a number' { get-free-name app app app-2 } --result app-3
export def get-free-name [base: string, ...taken: string]: nothing -> string {
    mut candidate = $base
    mut suffix = 1

    while $candidate in $taken {
        $suffix += 1
        $candidate = $'($base)-($suffix)'
    }

    $candidate
}

# Return a path with the home directory written as a tilde.
@example 'a tilde replaces the home' { with-env {HOME: /h} { get-display-path /h/code } } --result '~/code'
export def get-display-path [path: string]: nothing -> string {
    let relative = try {
        $path | path relative-to $env.HOME
    } catch {
        null
    }

    if $relative == null {
        return $path
    }

    if ($relative | is-empty) {
        return '~'
    }

    ['~' $relative] | path join
}

# Return the row of a session, or fail when no session has that name.
export def get-session [name: string]: nothing -> record<name: string, path: string, socket: string> {
    let session = find-session $name

    if $session == null {
        fail $'No session is named ($name).'
    }

    $session
}

# Resolve a session name or a directory to the name and the directory of a session.
export def resolve-target [target: string]: nothing -> record<name: string, path: string> {
    let named = find-session $target

    if $named != null {
        return ($named | select name path)
    }

    let directory = $target | path expand

    if ($directory | path type) != 'dir' {
        fail $'No session is named ($target), and ($directory) is not a directory.'
    }

    let existing = run-sql 'select name, path from sessions where path = :path' --params {path: $directory}
    | get --optional 0

    if $existing != null {
        return $existing
    }

    {
        name: (
            get-free-name (get-session-name $directory) ...(run-sql 'select name from sessions' | get name)
        )
        path: $directory
    }
}

# Create a session, or update its directory.
export def save-session [name: string, path: path]: nothing -> nothing {
    let upsert = 'insert into sessions (name, path, socket, created_at)
        values (:name, :path, :socket, :now)
        on conflict (name) do update set path = excluded.path, socket = excluded.socket'

    run-sql $upsert --params {
        name: $name
        path: $path
        socket: (get-socket $name)
        now: (get-time)
    } | ignore
}

# Return the sessions with their sockets and attachment times, ordered by name.
export def list-sessions []: nothing -> table {
    run-sql 'select name, path, socket, attached_at from sessions order by name'
}

# Return the sessions ordered by the most recent attachment.
export def list-recent-sessions []: nothing -> table {
    run-sql 'select name, path, socket from sessions order by attached_at desc'
}

# Return the name of the session that was attached before the current one.
export def get-previous-session-name []: nothing -> oneof<string, nothing> {
    let previous = run-sql '
        select name from sessions where attached_at is not null
        order by attached_at desc limit 1 offset 1'
    | get --optional 0

    if $previous == null {
        return null
    }

    $previous.name
}

# Record that a session is attached now.
export def touch-session [name: string]: nothing -> nothing {
    run-sql 'update sessions set attached_at = :now where name = :name' --params {
        now: (get-time)
        name: $name
    } | ignore
}

# Forget a session.
export def delete-session [name: string]: nothing -> nothing {
    run-sql 'delete from sessions where name = :name' --params {name: $name} | ignore
}
