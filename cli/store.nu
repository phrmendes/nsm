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
export def find-session [name: string]: nothing -> oneof<record, nothing> {
    run-sql 'select name, path, socket from sessions where name = :name' --params {name: $name}
    | get --optional 0
}

# Return the session that uses a directory, or nothing when no session does.
export def find-session-by-path [path: path]: nothing -> oneof<record, nothing> {
    run-sql 'select name, path from sessions where path = :path' --params {path: $path}
    | get --optional 0
}

# Return the name of every session.
export def list-session-names []: nothing -> list<string> {
    run-sql 'select name from sessions' | get name
}

# Create the socket path for a new session row.
def make-socket-path [name: string]: nothing -> string {
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

# Return the row of a session, or fail when no session has that name.
export def get-session [name: string]: nothing -> record<name: string, path: string, socket: string> {
    let session = find-session $name

    if $session == null {
        fail $'No session is named ($name).'
    }

    $session
}

# Create a session, or update its directory.
export def save-session [name: string, path: path]: nothing -> record<name: string, path: string, socket: string> {
    let upsert = 'insert into sessions (name, path, socket, created_at)
        values (:name, :path, :socket, :now)
        on conflict (name) do update set path = excluded.path'

    run-sql $upsert --params {
        name: $name
        path: $path
        socket: (make-socket-path $name)
        now: (get-time)
    } | ignore

    get-session $name
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
