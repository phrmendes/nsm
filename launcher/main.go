// Command nsm unpacks its bundle (Nushell and the nsm scripts) once, and runs it.
//
// The same file also acts as `setsid` and `timeout`, chosen from the name that
// started it, so the bundle needs no other tool.
package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// bundleID names the folder of the unpacked bundle. The build sets it.
var bundleID = "dev"

// tools are the names that the unpacked bin folder links to this file.
var tools = []string{"setsid", "timeout"}

func main() {
	switch filepath.Base(os.Args[0]) {
	case "setsid":
		os.Exit(runSetsid(os.Args[1:]))
	case "timeout":
		os.Exit(runTimeout(os.Args[1:]))
	}

	if err := launch(bundle, bundleID, os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "nsm: %v\n", err)
		os.Exit(1)
	}
}

// launch unpacks the bundle when its folder is missing, and replaces this process with Nushell.
func launch(data []byte, id string, args []string) error {
	if len(data) == 0 {
		return errors.New("this build has no bundle")
	}

	exe, err := os.Executable()
	if err != nil {
		return err
	}

	cache, err := os.UserCacheDir()
	if err != nil {
		return err
	}

	root := filepath.Join(cache, "nsm")
	dir := filepath.Join(root, id)
	nu := filepath.Join(dir, "bin", "nu")

	if err := ensureSafeFolder(root); err != nil {
		return err
	}

	if _, err := os.Stat(nu); err != nil {
		if err := unpack(bytes.NewReader(data), root, id); err != nil {
			return fmt.Errorf("cannot unpack into %s: %w", root, err)
		}
	}

	if err := linkTools(dir, exe); err != nil {
		return err
	}

	argv := []string{"nu", "--no-config-file", filepath.Join(dir, "share", "nsm", "cli", "main.nu")}
	argv = append(argv, args...)

	err = syscall.Exec(nu, argv, withPath(os.Environ(), filepath.Join(dir, "bin")))
	if errors.Is(err, os.ErrPermission) {
		return fmt.Errorf("cannot run %s. The folder %s may be mounted noexec", nu, root)
	}

	return err
}

// ensureSafeFolder checks the cache folder when it exists. The unpack step creates it otherwise.
func ensureSafeFolder(root string) error {
	if _, err := os.Lstat(root); err != nil {
		return nil
	}

	return ensureSafeRoot(root, os.Getuid())
}

// withPath puts a folder first on PATH.
func withPath(env []string, folder string) []string {
	path := folder

	out := make([]string, 0, len(env)+1)
	for _, entry := range env {
		if rest, ok := strings.CutPrefix(entry, "PATH="); ok {
			if rest != "" {
				path = folder + string(os.PathListSeparator) + rest
			}
			continue
		}
		out = append(out, entry)
	}

	return append(out, "PATH="+path)
}

// linkTools makes bin/<tool> a link to the executable, and repairs a link that points elsewhere.
func linkTools(dir, exe string) error {
	for _, name := range tools {
		link := filepath.Join(dir, "bin", name)

		if current, err := os.Readlink(link); err == nil && current == exe {
			continue
		}

		next := link + ".new"
		_ = os.Remove(next)

		if err := os.Symlink(exe, next); err != nil {
			return err
		}

		if err := os.Rename(next, link); err != nil {
			return err
		}
	}

	return nil
}
