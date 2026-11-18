use lib.nu [fail]

const COMPLETERS = {
    attach: {target: sessions}
    start: {target: sessions}
    kill: {name: sessions}
    completions: {shell: shells}
}

const BASH = '_nsm() {
    local word=${COMP_WORDS[COMP_CWORD]}
    local command=${COMP_WORDS[1]}

    if [ "$COMP_CWORD" -eq 1 ]; then
        mapfile -t COMPREPLY < <(compgen -W "@COMMANDS@" -- "$word")
        return
    fi

    case $command in
    attach | a | start)
        mapfile -t COMPREPLY < <(compgen -W "$(nsm names 2>/dev/null)" -- "$word"; compgen -d -- "$word")
        ;;
    kill | k)
        mapfile -t COMPREPLY < <(compgen -W "$(nsm names 2>/dev/null)" -- "$word")
        ;;
    completions)
        mapfile -t COMPREPLY < <(compgen -W "bash zsh nu" -- "$word")
        ;;
    esac
}

complete -F _nsm nsm
'

const ZSH = '#compdef nsm
_nsm() {
    local -a commands names
    commands=(@COMMANDS@)

    if (( CURRENT == 2 )); then
        _describe "command" commands
        return
    fi

    case $words[2] in
    attach | a | start)
        names=(${(f)"$(nsm names 2>/dev/null)"})
        _describe "session" names
        _files -/
        ;;
    kill | k)
        names=(${(f)"$(nsm names 2>/dev/null)"})
        _describe "session" names
        ;;
    completions)
        _values "shell" bash zsh nu
        ;;
    esac
}

compdef _nsm nsm
'

# Return the command names and the short forms, separated by spaces.
def get-command-words [commands: table<name: string, short: oneof<string, nothing>>]: nothing -> string {
    $commands | get name | append ($commands | get short | compact) | str join ' '
}

# Return the parameters of a command as the text of a Nushell `extern`.
def get-extern-parameters [command: record<name: string, parameters: list<record<name: string, kind: string, shape: oneof<string, nothing>, short: oneof<string, nothing>, optional: bool>>>]: nothing -> string {
    $command.parameters
    | each {|parameter|
        let completer = $COMPLETERS | get --optional $command.name | get --optional $parameter.name
        let shape = if $completer == null { $parameter.shape } else { $'($parameter.shape)@"nu-complete nsm ($completer)"' }
        let short = if $parameter.short == null { '' } else { ['(-' $parameter.short ')'] | str join }

        match $parameter.kind {
            positional => $'($parameter.name)(if $parameter.optional { '?' }): ($shape)'
            switch => $'--($parameter.name)($short)'
            _ => $'--($parameter.name)($short): ($shape)'
        }
    }
    | str join ', '
}

# Return the Nushell script with one `extern` for each command and short form.
def get-nushell-script [commands: table<name: string, short: oneof<string, nothing>, parameters: list<record<name: string, kind: string, shape: oneof<string, nothing>, short: oneof<string, nothing>, optional: bool>>>]: nothing -> string {
    let externs = $commands
    | each {|command|
        let parameters = get-extern-parameters $command

        [$command.name $command.short]
        | compact
        | each {|name| $'export extern "nsm ($name)" [($parameters)]' }
    }
    | flatten

    [
        'def "nu-complete nsm sessions" [] { ^nsm names | lines }'
        'def "nu-complete nsm shells" [] { [bash zsh nu] }'
        'export extern "nsm" [--version(-v)]'
        ...$externs
    ] | str join (char nl) | $in + (char nl)
}

# Return the script that completes nsm in the shell `bash`, `zsh`, or `nu`.
export def get-completions [shell: string, commands: table<name: string, short: oneof<string, nothing>, parameters: list<record<name: string, kind: string, shape: oneof<string, nothing>, short: oneof<string, nothing>, optional: bool>>>]: nothing -> string {
    match $shell {
        bash => ($BASH | str replace '@COMMANDS@' (get-command-words $commands))
        zsh => ($ZSH | str replace '@COMMANDS@' (get-command-words $commands))
        nu => (get-nushell-script $commands)
        _ => (fail $'Unknown shell ($shell). Use bash, zsh, or nu.')
    }
}
