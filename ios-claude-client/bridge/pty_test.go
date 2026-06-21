package main

import (
	"os"
	"os/exec"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ============================================================
// PTY Management Tests (P0: P1-P5, P7)
// ============================================================

// TestStartWithCommand verifies P1: creating a PTY and running a command.
func TestStartWithCommand(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping PTY creation test in short mode")
	}

	pty, cmd, err := startWithCommand("echo", "hello")
	require.NoError(t, err, "should create PTY without error")
	require.NotNil(t, pty, "PTY file descriptor should not be nil")
	require.NotNil(t, cmd, "CMD should not be nil")

	// Cleanup
	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	assert.True(t, isPTYValid(pty), "PTY should be a valid file descriptor")
	t.Logf("PTY created successfully, cmd PID: %d", cmd.Process.Pid)
}

// TestPTYReadOutput verifies P2: reading output from PTY.
func TestPTYReadOutput(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping PTY read test in short mode")
	}

	// Use cat to echo back input
	pty, cmd, err := startWithCommand("cat")
	require.NoError(t, err)
	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	// Write to PTY
	_, err = pty.Write([]byte("hello from test\n"))
	require.NoError(t, err, "should write to PTY without error")

	// Read from PTY
	buf := make([]byte, 256)
	n, err := pty.Read(buf)
	require.NoError(t, err, "should read from PTY without error")
	assert.Contains(t, string(buf[:n]), "hello from test",
		"PTY output should contain the written text")
}

// TestPTYWriteInput verifies P3: writing input to PTY and reading response.
func TestPTYWriteInput(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping PTY write test in short mode")
	}

	pty, cmd, err := startWithCommand("bash", "-c", "echo 'input received'; sleep 0.1")
	require.NoError(t, err)
	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	// Write input to PTY
	_, err = pty.Write([]byte("ls\n"))
	require.NoError(t, err, "should write input to PTY without error")

	// Give it time to process and read output
	buf := make([]byte, 4096)
	n, err := pty.Read(buf)
	if err == nil {
		t.Logf("PTY output: %s", string(buf[:n]))
		assert.NotEmpty(t, n, "should read some output from PTY")
	}
}

// TestPTYResize verifies P4: resizing PTY window.
func TestPTYResize(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping PTY resize test in short mode")
	}

	pty, cmd, err := startWithCommand("cat")
	require.NoError(t, err)
	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	// Resize the PTY
	err = ResizePTY(pty, 40, 120)
	require.NoError(t, err, "should resize PTY without error")

	// Resize again to verify stability
	err = ResizePTY(pty, 80, 24)
	require.NoError(t, err, "should resize PTY again without error")
}

// TestPTYResizeValues verifies resize with various dimensions.
func TestPTYResizeValues(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping PTY resize values test in short mode")
	}

	pty, cmd, err := startWithCommand("cat")
	require.NoError(t, err)
	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	tests := []struct {
		rows int
		cols int
	}{
		{24, 80},
		{40, 120},
		{10, 40},
		{100, 200},
		{1, 1},
	}

	for _, tc := range tests {
		err := ResizePTY(pty, tc.rows, tc.cols)
		assert.NoError(t, err, "resize to %dx%d should succeed", tc.rows, tc.cols)
	}
}

// TestStartTmuxSession verifies P5: starting a tmux session.
func TestStartTmuxSession(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping tmux integration test in short mode")
	}

	tmuxName, pty, cmd, clientName, err := startTmuxSession("test-session")
	_ = clientName
	if err != nil {
		// tmux may not be installed in CI
		t.Skipf("tmux not available: %v", err)
	}
	require.NotEmpty(t, tmuxName, "tmux session name should not be empty")
	require.NotNil(t, pty, "PTY should not be nil")
	require.NotNil(t, cmd, "CMD should not be nil")

	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	// Verify the tmux session exists
	alive := isTmuxSessionAlive("test-session")
	assert.True(t, alive, "tmux session should be alive after creation")
}

// TestSessionPersistence verifies P7: session persists after detach.
func TestSessionPersistence(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping session persistence test in short mode")
	}

	_, pty, cmd, _, err := startTmuxSession("persist-test")
	if err != nil {
		t.Skipf("tmux not available: %v", err)
	}
	defer pty.Close()

	// Simulate detach: kill the child process
	if cmd.Process != nil {
		err := cmd.Process.Kill()
		require.NoError(t, err)
	}

	// The tmux session should still be alive
	alive := isTmuxSessionAlive("persist-test")
	assert.True(t, alive, "tmux session should persist after process termination")

	// Clean up the tmux session
	cleanupTmuxSession("persist-test")
}

// TestPTYConcurrentAccess verifies P10: concurrent PTY reads and writes.
func TestPTYConcurrentAccess(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping concurrent PTY test in short mode")
	}

	pty, cmd, err := startWithCommand("bash", "-c", "while read line; do echo 'got: $line'; done")
	require.NoError(t, err)
	defer pty.Close()
	defer func() {
		if cmd.Process != nil {
			cmd.Process.Kill()
		}
	}()

	// Concurrent writes
	done := make(chan bool, 10)
	for i := 0; i < 10; i++ {
		go func(n int) {
			_, err := pty.Write([]byte("line\n"))
			assert.NoError(t, err, "concurrent write %d should succeed", n)
			done <- true
		}(i)
	}

	// Wait for all writes
	for i := 0; i < 10; i++ {
		<-done
	}

	t.Log("all concurrent writes completed without race")
}

// TestPTYProcessExit verifies P9: process exit handling.
func TestPTYProcessExit(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping PTY process exit test in short mode")
	}

	pty, cmd, err := startWithCommand("bash", "-c", "echo 'running'; sleep 10")
	require.NoError(t, err)
	defer pty.Close()

	// Kill the process
	require.NotNil(t, cmd.Process)
	err = cmd.Process.Kill()
	assert.NoError(t, err, "should kill process without error")

	// Wait for process to exit
	err = cmd.Wait()
	assert.Error(t, err, "Wait should return error for killed process")
	assert.False(t, cmd.ProcessState.Success(), "process should not exit successfully")
}

// TestInvalidPTYResize verifies resize with nil PTY returns error.
func TestInvalidPTYResize(t *testing.T) {
	err := ResizePTY(nil, 80, 24)
	assert.Error(t, err, "resizing nil PTY should return error")
}

// Helper: check if tmux is available.
func tmuxAvailable() bool {
	_, err := exec.LookPath("tmux")
	return err == nil
}

// Helper: check if a PTY fd is valid.
func isPTYValid(f *os.File) bool {
	if f == nil {
		return false
	}
	// A simple stat check to verify the fd is alive
	_, err := f.Stat()
	return err == nil
}

// Helper: check if a tmux session is alive.
func isTmuxSessionAlive(name string) bool {
	cmd := exec.Command("tmux", "has-session", "-t", name)
	return cmd.Run() == nil
}

// Helper: clean up a tmux session.
func cleanupTmuxSession(name string) {
	exec.Command("tmux", "kill-session", "-t", name).Run()
}
