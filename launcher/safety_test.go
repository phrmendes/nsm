package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureSafeRoot(t *testing.T) {
	uid := os.Getuid()

	cases := []struct {
		name    string
		mode    os.FileMode
		uid     int
		symlink bool
		wantErr bool
	}{
		{"a private folder", 0o700, uid, false, false},
		{"a folder that others can read", 0o755, uid, false, false},
		{"a folder that the group can write", 0o775, uid, false, true},
		{"a folder that everyone can write", 0o777, uid, false, true},
		{"a folder of another user", 0o700, uid + 1, false, true},
		{"a link to a folder", 0o700, uid, true, true},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			parent := t.TempDir()
			folder := filepath.Join(parent, "nsm")

			if err := os.Mkdir(folder, 0o700); err != nil {
				t.Fatal(err)
			}
			if err := os.Chmod(folder, test.mode); err != nil {
				t.Fatal(err)
			}

			path := folder
			if test.symlink {
				path = filepath.Join(parent, "link")
				if err := os.Symlink(folder, path); err != nil {
					t.Fatal(err)
				}
			}

			err := ensureSafeRoot(path, test.uid)
			if (err != nil) != test.wantErr {
				t.Fatalf("error %v, want error %v", err, test.wantErr)
			}
		})
	}
}

func TestUnpackCreatesAPrivateRootAndReadOnlyFiles(t *testing.T) {
	root := filepath.Join(t.TempDir(), "nsm")

	if err := unpack(bytes.NewReader(makeArchive(t, sample)), root, "abc"); err != nil {
		t.Fatal(err)
	}

	info, err := os.Stat(root)
	if err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("root mode %v (%v), want 0700", info.Mode().Perm(), err)
	}

	for path, want := range map[string]os.FileMode{
		filepath.Join(root, "abc", "bin", "nu"):                      0o555,
		filepath.Join(root, "abc", "share", "nsm", "cli", "main.nu"): 0o444,
	} {
		info, err := os.Stat(path)
		if err != nil || info.Mode().Perm() != want {
			t.Errorf("%s mode %v (%v), want %v", filepath.Base(path), info.Mode().Perm(), err, want)
		}
	}
}
