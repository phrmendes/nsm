use lib.nu [fail get-display-path]

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
            projects: []
            icons: $DEFAULT_ICONS
            restore: {file: null}
        }
    }

    let user = try {
        open $file
    } catch {|err|
        fail $'Cannot read (get-display-path $file): ($err.msg)'
    }

    let projects = $user | get --optional projects | default []

    {
        projects: $projects
        icons: ($DEFAULT_ICONS | merge ($user.icons? | default {}))
        restore: {
            file: ($user | get --optional restore.file)
        }
    }
}
