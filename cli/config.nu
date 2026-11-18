use lib.nu [fail get-display-path]

const DEFAULT_ICONS = {
    running: '🟢'
    stored: '⚫'
    directory: '📁'
}

const DEFAULT_START = {
    environment: true
    timeout: 300
}

# Return the path of the configuration file.
def get-config-file []: nothing -> string {
    ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join .config)) | path join .nsm.nuon
}

# Return the configuration, with the defaults for the missing keys.
export def get-config []: nothing -> record<projects: list<string>, icons: record<running: string, stored: string, directory: string>, restore: record<file: oneof<string, nothing>>, start: record<environment: bool, timeout: int>> {
    let file = get-config-file

    if not ($file | path exists) {
        return {
            projects: []
            icons: $DEFAULT_ICONS
            restore: {file: null}
            start: $DEFAULT_START
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
        start: ($DEFAULT_START | merge ($user.start? | default {}))
    }
}
