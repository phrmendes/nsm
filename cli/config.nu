use lib.nu [fail]
use store.nu [get-display-path]

const DEFAULT_ICONS = {
    running: '🟢'
    stored: '⚫'
    directory: '📁'
}

# Return the path of the configuration file.
def get-config-file []: nothing -> string {
    ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join .config)) | path join .nsm.nuon
}

# Return the configuration, with the defaults for the missing keys.
export def get-config []: nothing -> record {
    let file = get-config-file

    if not ($file | path exists) {
        return {
            projects: {dir: null}
            icons: $DEFAULT_ICONS
            restore: {file: null}
        }
    }

    let user = try {
        open $file
    } catch {|err|
        fail $'Cannot read (get-display-path $file): ($err.msg)' $file --text file
    }

    let dir = $user | get --optional projects.dir
    let dir = if ($dir | is-empty) { null } else { $dir }

    {
        projects: {dir: $dir}
        icons: ($DEFAULT_ICONS | merge ($user.icons? | default {}))
        restore: {
            file: ($user | get --optional restore.file)
        }
    }
}
