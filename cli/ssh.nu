use lib.nu [fail]

# Return the SSH configuration file of the current user.
def get-ssh-config []: nothing -> string {
    $env.HOME | path join .ssh config
}

# Expand an Include pattern relative to ~/.ssh.
def expand-include [pattern: path]: nothing -> list<string> {
    let target = if ($pattern | str starts-with '/') or ($pattern | str starts-with '~') {
        $pattern | path expand
    } else {
        $env.HOME | path join .ssh $pattern
    }

    glob $target
}

# Read host aliases and Include patterns from one SSH configuration file.
def read-config [file: path, depth: int]: nothing -> record<hosts: list<string>, includes: list<string>> {
    if $depth > 10 or not ($file | path exists) {
        return {
            hosts: []
            includes: []
        }
    }

    let entries = try {
        open --raw $file
    } catch {|err|
        fail $'Cannot read ($file): ($err.msg)'
    }
    | lines
    | each {|line| $line | str trim }
    | where {|line| ($line | is-not-empty) and not ($line | str starts-with '#') }
    | each {|line| $line | split row --regex '\s+' }
    | where {|parts| ($parts | length) > 1 }

    let hosts = $entries
    | where {|parts| $parts.0? =~ '(?i)^host$' }
    | each {|parts| $parts | skip 1 }
    | flatten

    let includes = $entries
    | where {|parts| $parts.0? =~ '(?i)^include$' }
    | each {|parts| $parts | skip 1 }
    | flatten

    {hosts: $hosts, includes: $includes}
}

# Collect host aliases from one SSH configuration file and its includes.
def collect-hosts [file: path, depth: int]: nothing -> list<string> {
    let config = read-config $file $depth
    let included = $config.includes
    | each {|pattern| expand-include $pattern | each {|path| collect-hosts $path ($depth + 1) } }
    | flatten
    | flatten

    $config.hosts ++ $included
}

# Return the explicit host aliases in the SSH configuration, following Include.
export def list-ssh-hosts []: nothing -> list<string> {
    let file = get-ssh-config

    if not ($file | path exists) {
        return []
    }

    let hosts = try {
        collect-hosts $file 0
    } catch {|err|
        fail $'Cannot read ($file): ($err.msg)'
    }

    $hosts | where {|host| ($host | is-not-empty) and ($host !~ '[*?!]') } | uniq
}
