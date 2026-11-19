package main

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestRunTimeoutExitCodes(t *testing.T) {
	cases := []struct {
		name    string
		args    []string
		want    int
		atLeast time.Duration
		atMost  time.Duration
	}{
		{"a command that ends in time", []string{"5", "true"}, 0, 0, 2 * time.Second},
		{"the exit code of the command", []string{"5", "sh", "-c", "exit 7"}, 7, 0, 2 * time.Second},
		{"a command that runs too long", []string{"1", "sleep", "5"}, 124, time.Second, 3 * time.Second},
		{"a missing command", []string{"1", "nsm-no-such-command"}, 127, 0, 2 * time.Second},
		{"a bad duration", []string{"abc", "true"}, 125, 0, 2 * time.Second},
		{"a missing command argument", []string{"1"}, 125, 0, 2 * time.Second},
		{"a duration with a suffix", []string{"0.5s", "sleep", "5"}, 124, 500 * time.Millisecond, 3 * time.Second},
		{"a command that ends with a signal", []string{"5", "sh", "-c", "kill -9 $$"}, 137, 0, 2 * time.Second},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			started := time.Now()
			code := runTimeout(test.args)
			elapsed := time.Since(started)

			if code != test.want {
				t.Errorf("exit code %d, want %d", code, test.want)
			}
			if elapsed < test.atLeast || elapsed > test.atMost {
				t.Errorf("took %v, want between %v and %v", elapsed, test.atLeast, test.atMost)
			}
		})
	}
}

func TestRunSetsidForkReturnsAtOnceAndStartsANewSession(t *testing.T) {
	out := filepath.Join(t.TempDir(), "ids")
	script := "sleep 0.3; ps -o pid=,sid= -p $$ > " + out

	started := time.Now()
	if code := runSetsid([]string{"--fork", "sh", "-c", script}); code != 0 {
		t.Fatalf("exit code %d", code)
	}
	if elapsed := time.Since(started); elapsed > 250*time.Millisecond {
		t.Fatalf("--fork took %v, want an immediate return", elapsed)
	}

	var text []byte
	for range 40 {
		time.Sleep(100 * time.Millisecond)
		if data, err := os.ReadFile(out); err == nil && len(data) > 0 {
			text = data
			break
		}
	}

	fields := strings.Fields(string(text))
	if len(fields) != 2 || fields[0] != fields[1] {
		t.Fatalf("the child is not a session leader: %q", text)
	}
	if sid, _ := strconv.Atoi(fields[1]); sid == os.Getpid() {
		t.Fatal("the child shares the session of the test")
	}
}

func TestRunSetsidWithoutForkWaitsAndKeepsTheExitCode(t *testing.T) {
	if code := runSetsid([]string{"sh", "-c", "exit 3"}); code != 3 {
		t.Fatalf("exit code %d, want 3", code)
	}
}

func TestRunSetsidRefusesBadUsage(t *testing.T) {
	for name, args := range map[string][]string{
		"no command":     {"--fork"},
		"unknown option": {"--nope", "true"},
	} {
		t.Run(name, func(t *testing.T) {
			if code := runSetsid(args); code != 125 {
				t.Fatalf("exit code %d, want 125", code)
			}
		})
	}
}
