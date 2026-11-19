package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	exitTimeout   = 124
	exitUsage     = 125
	exitNotRun    = 126
	exitNotFound  = 127
	killGrace     = 2 * time.Second
	maxInheritFDs = 1024
)

// runSetsid runs a command in a new session. With --fork, it returns at once.
func runSetsid(args []string) int {
	fork, wait := false, false

	for len(args) > 0 && strings.HasPrefix(args[0], "-") {
		switch args[0] {
		case "--fork", "-f":
			fork = true
		case "--wait", "-w":
			wait = true
		default:
			fmt.Fprintf(os.Stderr, "setsid: unsupported option %s\n", args[0])
			return exitUsage
		}
		args = args[1:]
	}

	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "setsid: a command is missing")
		return exitUsage
	}

	for fd := 3; fd < maxInheritFDs; fd++ {
		syscall.CloseOnExec(fd)
	}

	command := exec.Command(args[0], args[1:]...)
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr
	command.SysProcAttr = &syscall.SysProcAttr{Setsid: true}

	if err := command.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "setsid: %v\n", err)
		return startCode(err)
	}

	if fork && !wait {
		_ = command.Process.Release()
		return 0
	}

	return exitCode(command.Wait())
}

// runTimeout runs a command, and ends it after the given time with the exit code 124.
func runTimeout(args []string) int {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "timeout: a duration and a command are required")
		return exitUsage
	}

	limit, err := parseDuration(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "timeout: %v\n", err)
		return exitUsage
	}

	command := exec.Command(args[1], args[2:]...)
	command.Stdin, command.Stdout, command.Stderr = os.Stdin, os.Stdout, os.Stderr

	if err := command.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "timeout: %v\n", err)
		return startCode(err)
	}

	done := make(chan error, 1)
	go func() { done <- command.Wait() }()

	select {
	case err := <-done:
		return exitCode(err)
	case <-time.After(limit):
	}

	_ = command.Process.Signal(syscall.SIGTERM)

	select {
	case <-done:
	case <-time.After(killGrace):
		_ = command.Process.Kill()
		<-done
	}

	return exitTimeout
}

// parseDuration reads seconds, with an optional s, m, h, or d suffix.
func parseDuration(text string) (time.Duration, error) {
	unit := time.Second

	if last := text[len(text)-1:]; strings.Contains("smhd", last) {
		unit = map[string]time.Duration{"s": time.Second, "m": time.Minute, "h": time.Hour, "d": 24 * time.Hour}[last]
		text = text[:len(text)-1]
	}

	value, err := strconv.ParseFloat(text, 64)
	if err != nil || value < 0 {
		return 0, fmt.Errorf("%q is not a valid duration", text)
	}

	return time.Duration(value * float64(unit)), nil
}

// startCode maps a start failure to the exit code of a shell.
func startCode(err error) int {
	if errors.Is(err, os.ErrPermission) {
		return exitNotRun
	}
	return exitNotFound
}

// exitCode maps the end of a process to an exit code: the code itself, or 128 plus the signal.
func exitCode(err error) int {
	if err == nil {
		return 0
	}

	var failed *exec.ExitError
	if !errors.As(err, &failed) {
		return exitNotFound
	}

	if status, ok := failed.Sys().(syscall.WaitStatus); ok && status.Signaled() {
		return 128 + int(status.Signal())
	}

	return failed.ExitCode()
}
