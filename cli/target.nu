use lib.nu [fail]
use names.nu [get-free-name get-session-name]
use store.nu [find-session find-session-by-path list-session-names]

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

    let existing = find-session-by-path $directory

    if $existing != null {
        return $existing
    }

    {
        name: (get-free-name (get-session-name $directory) ...(list-session-names))
        path: $directory
    }
}
