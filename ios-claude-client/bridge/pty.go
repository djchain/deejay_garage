package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/creack/pty"
	"golang.org/x/sys/unix"
)

// setRawTermios disables local echo and canonical mode on the PTY slave
// through the master file descriptor. This prevents double-character echo
// (once from PTY local echo, once from the shell inside tmux).
func setRawTermios(fd uintptr) error {
	termios, err := unix.IoctlGetTermios(int(fd), unix.TIOCGETA)
	if err != nil {
		return fmt.Errorf("TIOCGETA: %w", err)
	}

	// Input flags: disable all processing
	termios.Iflag &^= unix.IGNBRK | unix.BRKINT | unix.PARMRK | unix.ISTRIP |
		unix.INLCR | unix.IGNCR | unix.ICRNL | unix.IXON
	// Output flags: disable post-processing
	termios.Oflag &^= unix.OPOST
	// Local flags: disable echo, canonical mode, signal chars, extended processing
	termios.Lflag &^= unix.ECHO | unix.ECHONL | unix.ICANON | unix.ISIG | unix.IEXTEN
	// Control flags: 8-bit chars, no parity
	termios.Cflag &^= unix.CSIZE | unix.PARENB
	termios.Cflag |= unix.CS8
	// Read: return each byte immediately (no buffering)
	termios.Cc[unix.VMIN] = 1
	termios.Cc[unix.VTIME] = 0

	return unix.IoctlSetTermios(int(fd), unix.TIOCSETA, termios)
}

// startWithCommand creates a PTY and runs the given command in it.
func startWithCommand(name string, args ...string) (*os.File, *exec.Cmd, error) {
	cmd := exec.Command(name, args...)
	f, err := pty.Start(cmd)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to start PTY for %s: %w", name, err)
	}
	// Disable local echo on the PTY slave to prevent double characters
	if err := setRawTermios(f.Fd()); err != nil {
		log.Printf("Warning: failed to set raw mode on PTY: %v", err)
		// Non-fatal: tmux will also set raw mode when it attaches
	}
	return f, cmd, nil
}

// resolveClientName finds the tmux client name for the given PID by
// querying `tmux list-clients`. Returns "" if no match is found.
func resolveClientName(pid int) string {
	out, err := exec.Command("tmux", "list-clients", "-F", "#{client_pid} #{client_name}").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			var clientPID int
			fmt.Sscanf(parts[0], "%d", &clientPID)
			if clientPID == pid {
				return parts[1]
			}
		}
	}
	return ""
}

// startTmuxSession creates a detached tmux session and attaches it to a PTY.
// If the tmux session already exists, it simply attaches to it.
// Returns (sessionName, ptyFile, cmd, clientName, error).
func startTmuxSession(sessionName string) (string, *os.File, *exec.Cmd, string, error) {
	// Step 0: Check if the tmux session already exists
	created := false
	hasSession := exec.Command("tmux", "has-session", "-t", sessionName)
	if hasSession.Run() != nil {
		// Session doesn't exist — create a new one starting in the user's home dir.
		homeDir, _ := os.UserHomeDir()
		if homeDir == "" {
			homeDir = os.Getenv("HOME")
		}
		create := exec.Command("tmux", "new-session", "-d", "-s", sessionName, "-c", homeDir)
		if err := create.Run(); err != nil {
			return "", nil, nil, "", fmt.Errorf("failed to create tmux session %s: %w", sessionName, err)
		}
		created = true
		log.Printf("Created new tmux session: %s", sessionName)
	} else {
		log.Printf("Tmux session %s already exists — attaching", sessionName)
	}

	// Step 2: Attach to the session via PTY for interactive I/O
	cmd := exec.Command("tmux", "attach-session", "-t", sessionName)
	f, err := pty.Start(cmd)
	if err != nil {
		// Only clean up the session if we created it
		if created {
			exec.Command("tmux", "kill-session", "-t", sessionName).Run()
		}
		return "", nil, nil, "", fmt.Errorf("failed to attach to tmux session %s: %w", sessionName, err)
	}
	// Disable local echo on the PTY slave to prevent double characters
	if err := setRawTermios(f.Fd()); err != nil {
		log.Printf("Warning: failed to set raw mode on PTY: %v", err)
	}

	// Resolve the tmux client name tied to this PTY's attach process.
	// This lets us target switch-client -c <name> instead of leaking through
	// $TMUX to the Mac's own client.
	clientName := resolveClientName(cmd.Process.Pid)
	if clientName == "" {
		log.Printf("Warning: could not resolve tmux client name for PID %d", cmd.Process.Pid)
	} else {
		log.Printf("Resolved tmux client name: %s (PID %d)", clientName, cmd.Process.Pid)
	}

	return sessionName, f, cmd, clientName, nil
}

// ResizePTY resizes a PTY's terminal window.
func ResizePTY(fd *os.File, rows, cols int) error {
	if fd == nil {
		return fmt.Errorf("nil PTY file descriptor")
	}
	return pty.Setsize(fd, &pty.Winsize{
		Cols: uint16(cols),
		Rows: uint16(rows),
	})
}
