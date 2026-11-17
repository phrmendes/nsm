use lib.nu [fail]

const COMMANDS = [
    [name, short];
    [attach, a]
    [switch, s]
    [last, l]
    [new, n]
    [list, ls]
    [pick, null]
    [start, null]
    [kill, k]
    [names, null]
    [completions, null]
]

const BASH = '_nsm() {
    local word=${COMP_WORDS[COMP_CWORD]}
    local command=${COMP_WORDS[1]}

    if [ "$COMP_CWORD" -eq 1 ]; then
        mapfile -t COMPREPLY < <(compgen -W "@COMMANDS@" -- "$word")
        return
    fi

    case $command in
    attach | a | start | kill | k)
        mapfile -t COMPREPLY < <(compgen -W "$(nsm names 2>/dev/null)" -- "$word"; compgen -d -- "$word")
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
    attach | a | start | kill | k)
        names=(${(f)"$(nsm names 2>/dev/null)"})
        _describe "session" names
        _files -/
        ;;
    completions)
        _values "shell" bash zsh nu
        ;;
    esac
}

compdef _nsm nsm
'

export def get-completions [shell: string]: nothing -> string {
    match $shell {
        bash => ($BASH | str replace '@COMMANDS@' (get-command-words))
        zsh => ($ZSH | str replace '@COMMANDS@' (get-command-words))
        nu => (get-nushell-script)
        _ => (fail $'Unknown shell ($shell). Use bash, zsh, or nu.')
    }
}

def get-command-words []: nothing -> string {
    $COMMANDS | get name | append ($COMMANDS | get short | compact) | str join ' '
}

def get-nushell-script []: nothing -> string {
    let signatures = {
        attach: 'target?: string@"nu-complete nsm sessions", --scope: string'
        switch: '--scope: string'
        last: '--print'
        new: 'name: string, path?: path'
        list: '--json'
        pick: '--sessions, --scope: string'
        start: 'target: string@"nu-complete nsm sessions"'
        kill: 'name?: string@"nu-complete nsm sessions", --all(-a), --force(-f), --scope: string'
        names: ''
        completions: 'shell: string@"nu-complete nsm shells"'
    }

    let externs = $COMMANDS
    | each {|command|
        let signature = $signatures | get $command.name
        let names = [$command.name $command.short] | compact

        $names | each {|name| $'export extern "nsm ($name)" [($signature)]' }
    }
    | flatten

    [
        'def "nu-complete nsm sessions" [] { ^nsm names | lines }'
        'def "nu-complete nsm shells" [] { [bash zsh nu] }'
        'export extern "nsm" [--version(-v)]'
        ...$externs
    ] | str join (char nl) | $in + (char nl)
}
