# Run every test file in its own process.
def main []: nothing -> nothing {
    let directory = $env.CURRENT_FILE | path dirname
    let files = glob $"($directory)/test_*.nu" | sort

    for file in $files {
        print $"🧪 ($file | path basename)"
        nu --no-config-file $file
    }

    print '✅ Tests completed successfully'
}
