package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type entry struct {
	name   string
	body   string
	mode   int64
	link   string
	isLink bool
}

func makeArchive(t *testing.T, entries []entry) []byte {
	t.Helper()

	var buffer bytes.Buffer
	zipped := gzip.NewWriter(&buffer)
	writer := tar.NewWriter(zipped)

	for _, item := range entries {
		header := &tar.Header{Name: item.name, Mode: item.mode, Size: int64(len(item.body))}
		if item.isLink {
			header.Typeflag, header.Linkname, header.Size = tar.TypeSymlink, item.link, 0
		}
		if err := writer.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if !item.isLink {
			if _, err := writer.Write([]byte(item.body)); err != nil {
				t.Fatal(err)
			}
		}
	}

	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := zipped.Close(); err != nil {
		t.Fatal(err)
	}

	return buffer.Bytes()
}

var sample = []entry{
	{name: "bin/nu", body: "#!/bin/sh\necho nu\n", mode: 0o755},
	{name: "share/nsm/cli/main.nu", body: "main", mode: 0o644},
	{name: "share/nsm/link", isLink: true, link: "cli/main.nu"},
}

func TestUnpackRestoresFilesModesAndLinks(t *testing.T) {
	root := t.TempDir()

	if err := unpack(bytes.NewReader(makeArchive(t, sample)), root, "abc"); err != nil {
		t.Fatal(err)
	}

	info, err := os.Stat(filepath.Join(root, "abc", "bin", "nu"))
	if err != nil || info.Mode().Perm()&0o111 == 0 {
		t.Fatalf("bin/nu is not executable: %v %v", info, err)
	}

	body, err := os.ReadFile(filepath.Join(root, "abc", "share", "nsm", "link"))
	if err != nil || string(body) != "main" {
		t.Fatalf("the link does not reach the file: %q %v", body, err)
	}
}

func TestUnpackRefusesPathsOutsideTheFolder(t *testing.T) {
	cases := []struct {
		name    string
		entries []entry
	}{
		{"a parent path", []entry{{name: "../escape", body: "x", mode: 0o644}}},
		{"a link to the parent", []entry{{name: "link", isLink: true, link: "../outside"}}},
		{"a link to an absolute path", []entry{{name: "link", isLink: true, link: "/etc/passwd"}}},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			root := t.TempDir()

			if err := unpack(bytes.NewReader(makeArchive(t, test.entries)), root, "abc"); err == nil {
				t.Fatal("expected an error")
			}

			if _, err := os.Stat(filepath.Join(root, "abc")); err == nil {
				t.Fatal("a failed unpack left the target folder")
			}
		})
	}
}

func TestUnpackKeepsAnAbsoluteNameInsideTheFolder(t *testing.T) {
	root := t.TempDir()

	if err := unpack(bytes.NewReader(makeArchive(t, []entry{{name: "/abs/file", body: "x", mode: 0o644}})), root, "abc"); err != nil {
		t.Fatal(err)
	}

	if _, err := os.Stat(filepath.Join(root, "abc", "abs", "file")); err != nil {
		t.Fatalf("the file is not below the target folder: %v", err)
	}
}

func TestUnpackIsSafeInParallel(t *testing.T) {
	root := t.TempDir()
	archive := makeArchive(t, sample)

	var group sync.WaitGroup
	errs := make(chan error, 16)

	for range 16 {
		group.Add(1)
		go func() {
			defer group.Done()
			errs <- unpack(bytes.NewReader(archive), root, "abc")
		}()
	}

	group.Wait()
	close(errs)

	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}

	entries, _ := os.ReadDir(root)
	if len(entries) != 1 || entries[0].Name() != "abc" {
		t.Fatalf("expected only the folder abc, got %v", entries)
	}
}

func TestUnpackCleansOldFolders(t *testing.T) {
	root := t.TempDir()
	old := filepath.Join(root, "old")
	fresh := filepath.Join(root, ".tmp-fresh")
	stale := filepath.Join(root, ".tmp-stale")

	for _, dir := range []string{old, fresh, stale} {
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}

	past := time.Now().Add(-2 * staleAfter)
	if err := os.Chtimes(stale, past, past); err != nil {
		t.Fatal(err)
	}

	if err := unpack(bytes.NewReader(makeArchive(t, sample)), root, "new"); err != nil {
		t.Fatal(err)
	}

	for dir, want := range map[string]bool{old: false, stale: false, fresh: true, filepath.Join(root, "new"): true} {
		_, err := os.Stat(dir)
		if (err == nil) != want {
			t.Errorf("%s: exists=%v, want %v", filepath.Base(dir), err == nil, want)
		}
	}
}
