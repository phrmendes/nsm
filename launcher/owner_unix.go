package main

import (
	"os"
	"syscall"
)

// ownerOf returns the user id that owns a file.
func ownerOf(info os.FileInfo) (int, bool) {
	status, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, false
	}

	return int(status.Uid), true
}
