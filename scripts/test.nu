# Run the test suites of nsm.
def main []: nothing -> nothing {
    let root = $env.CURRENT_FILE | path dirname | path dirname

    print '🧪 Running the Nushell tests...'
    nu ($root | path join tests/cli/tests.nu)

    print '🧪 Running the Lua tests...'
    nvim --headless --noplugin -u ($root | path join scripts/init.lua) -c 'lua MiniTest.run()' -c 'qa!'

    print '🧪 Running the Go tests...'
    cd ($root | path join launcher)
    go test -count=1 ./...
}
