package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWithPathPutsTheFolderFirst(t *testing.T) {
	cases := []struct {
		name string
		env  []string
		want string
	}{
		{"an existing PATH", []string{"A=1", "PATH=/usr/bin"}, "PATH=/x/bin" + string(os.PathListSeparator) + "/usr/bin"},
		{"an empty PATH", []string{"PATH="}, "PATH=/x/bin"},
		{"no PATH", []string{"A=1"}, "PATH=/x/bin"},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			got := withPath(test.env, "/x/bin")

			var paths []string
			for _, entry := range got {
				if strings.HasPrefix(entry, "PATH=") {
					paths = append(paths, entry)
				}
			}

			if len(paths) != 1 || paths[0] != test.want {
				t.Fatalf("got %v, want %q", paths, test.want)
			}
		})
	}
}

func TestLinkToolsCreatesAndRepairsLinks(t *testing.T) {
	dir := t.TempDir()
	if err := os.Mkdir(filepath.Join(dir, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}

	for _, exe := range []string{"/first/nsm", "/first/nsm", "/second/nsm"} {
		if err := linkTools(dir, exe); err != nil {
			t.Fatal(err)
		}

		for _, name := range tools {
			target, err := os.Readlink(filepath.Join(dir, "bin", name))
			if err != nil || target != exe {
				t.Fatalf("%s links to %q (%v), want %q", name, target, err, exe)
			}
		}
	}
}

func TestLaunchRefusesABuildWithoutBundle(t *testing.T) {
	if err := launch(nil, "x", nil); err == nil {
		t.Fatal("expected an error")
	}
}
