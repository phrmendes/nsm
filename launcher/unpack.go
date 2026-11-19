package main

import (
	"archive/tar"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// staleAfter is the age after which an unfinished unpack folder counts as abandoned.
const staleAfter = time.Hour

// unpack extracts the tar.gz bundle into root/id through a temporary folder, so a reader sees all of it or none of it.
func unpack(bundle io.Reader, root, id string) error {
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}

	if err := ensureSafeRoot(root, os.Getuid()); err != nil {
		return err
	}

	temporary, err := os.MkdirTemp(root, ".tmp-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temporary)

	if err := extract(bundle, temporary); err != nil {
		return err
	}

	target := filepath.Join(root, id)

	if err := os.Rename(temporary, target); err != nil {
		if _, statErr := os.Stat(target); statErr == nil {
			return nil
		}
		return err
	}

	return removeOthers(root, id)
}

// extract writes the files of a tar.gz below a folder, and refuses a path that leaves it.
func extract(bundle io.Reader, folder string) error {
	zipped, err := gzip.NewReader(bundle)
	if err != nil {
		return err
	}
	defer zipped.Close()

	reader := tar.NewReader(zipped)

	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}

		path := filepath.Join(folder, header.Name)
		if path != folder && !strings.HasPrefix(path, folder+string(os.PathSeparator)) {
			return fmt.Errorf("the archive has the path %q outside the folder", header.Name)
		}

		switch header.Typeflag {
		case tar.TypeDir:
			err = os.MkdirAll(path, 0o755)
		case tar.TypeReg:
			err = writeFile(path, reader, readOnly(header.FileInfo().Mode().Perm()))
		case tar.TypeSymlink:
			err = writeLink(folder, path, header.Linkname)
		default:
			err = fmt.Errorf("the archive has the unsupported entry %q", header.Name)
		}
		if err != nil {
			return err
		}
	}
}

// readOnly removes the write bits from a file mode, and keeps the execute bits.
func readOnly(mode os.FileMode) os.FileMode {
	return mode &^ 0o222
}

// ensureSafeRoot refuses a cache folder that another user owns, that others can write to, or that is a link.
func ensureSafeRoot(root string, uid int) error {
	info, err := os.Lstat(root)
	if err != nil {
		return err
	}

	if !info.IsDir() {
		return fmt.Errorf("%s is not a folder", root)
	}

	if info.Mode().Perm()&0o022 != 0 {
		return fmt.Errorf("%s can be written by other users. Run chmod go-w on it", root)
	}

	if owner, ok := ownerOf(info); ok && owner != uid {
		return fmt.Errorf("%s belongs to another user", root)
	}

	return nil
}

func writeFile(path string, source io.Reader, mode os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}

	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode|0o200)
	if err != nil {
		return err
	}

	if _, err := io.Copy(file, source); err != nil {
		file.Close()
		return err
	}

	if err := file.Close(); err != nil {
		return err
	}

	return os.Chmod(path, mode)
}

// writeLink creates a symbolic link, and refuses a target that leaves the folder.
func writeLink(folder, path, target string) error {
	resolved := target
	if !filepath.IsAbs(target) {
		resolved = filepath.Join(filepath.Dir(path), target)
	}

	if resolved != folder && !strings.HasPrefix(resolved, folder+string(os.PathSeparator)) {
		return fmt.Errorf("the archive links %q outside the folder", target)
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}

	return os.Symlink(target, path)
}

// removeOthers deletes the folders of other bundles, and the unpack folders that nobody finishes.
func removeOthers(root, keep string) error {
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}

	for _, entry := range entries {
		if !entry.IsDir() || entry.Name() == keep {
			continue
		}

		if strings.HasPrefix(entry.Name(), ".tmp-") {
			info, err := entry.Info()
			if err != nil || time.Since(info.ModTime()) < staleAfter {
				continue
			}
		}

		_ = os.RemoveAll(filepath.Join(root, entry.Name()))
	}

	return nil
}
