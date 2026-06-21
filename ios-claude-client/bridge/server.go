package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

//go:embed web/*
var webFS embed.FS

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

// startPTYReader reads from ptyFile and writes PTY output to conn as JSON
// output messages. It closes doneCh when the PTY exits (EOF or error).
func startPTYReader(ptyFile *os.File, conn *websocket.Conn) chan struct{} {
	doneCh := make(chan struct{})
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := ptyFile.Read(buf)
			if err != nil {
				if err != io.EOF {
					log.Printf("PTY read error: %v", err)
				}
				close(doneCh)
				return
			}
			if n > 0 {
				output := map[string]string{
					"type": "output",
					"data": string(buf[:n]),
				}
				if err := conn.WriteJSON(output); err != nil {
					log.Printf("WebSocket write error: %v", err)
					close(doneCh)
					return
				}
			}
		}
	}()
	return doneCh
}

// listAndSendSessions runs tmux list-sessions and sends the result to the client.
// When no tmux server is running (e.g. after the last session was killed), an
// empty list is returned instead of an error so the client can show the correct
// "No Tmux Sessions" state.
func listAndSendSessions(conn *websocket.Conn, currentSession ...string) {
	out, err := exec.Command("tmux", "list-sessions", "-F", "#S #{session_windows}").Output()
	if err != nil {
		// No tmux server running — return an empty list, not an error.
		conn.WriteJSON(map[string]interface{}{
			"type":     "session_list",
			"sessions": []SessionInfo{},
		})
		return
	}
	var sessions []SessionInfo
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) >= 2 {
			windows := 0
			fmt.Sscanf(parts[1], "%d", &windows)
			sessions = append(sessions, SessionInfo{Name: parts[0], Windows: windows})
		}
	}
	resp := map[string]interface{}{
		"type":     "session_list",
		"sessions": sessions,
	}
	if len(currentSession) > 0 && currentSession[0] != "" {
		resp["current_session"] = currentSession[0]
	}
	conn.WriteJSON(resp)
}

// handleWebSocket handles incoming WebSocket connections at /ws.
func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade failed: %v", err)
		return
	}
	defer conn.Close()

	log.Printf("WebSocket client connected")
	log.Printf("WebSocket client from: %s", r.RemoteAddr)

	// Get or create a session (default session name from CLI flags)
	session := getOrCreateSession()
	if session == nil {
		log.Printf("No session available")
		return
	}

	// Set tmux session name if not already set
	if session.TmuxName == "" {
		session.TmuxName = session.Name
	}

	// Always create a fresh PTY attachment for each WebSocket connection.
	// Close any stale PTY from a previous connection (e.g., after Ctrl-D EOF
	// caused tmux to exit, or a previous disconnect left a dead PTY fd).
	if session.PTY != nil {
		session.PTY.Close()
		session.PTY = nil
	}
	session.Cmd = nil

	_, ptyFile, cmd, clientName, err := startTmuxSession(session.TmuxName)
	if err != nil {
		log.Printf("Failed to start tmux session: %v", err)
		conn.WriteJSON(map[string]string{
			"type": "output",
			"data": "\r\n\x1b[31mFailed to start tmux session\x1b[0m\r\n",
		})
		return
	}
	session.PTY = ptyFile
	session.Cmd = cmd
	session.ClientName = clientName
	session.Active = true
	log.Printf("Tmux session %s attached (client: %s)", session.TmuxName, clientName)

	// Disable status bar only for this session as seen from this bridge client.
	// Other clients (e.g. native Mac terminals) keep their status bars intact.
	if err := exec.Command("tmux", "set-option", "-t", session.TmuxName, "status", "off").Run(); err != nil {
		log.Printf("Warning: failed to disable status on session %s: %v", session.TmuxName, err)
	}

	// ── Let the shell prompt settle before capture ───────────────────
	// Without this pause, capture-pane may race with the shell's initial
	// escape sequences (cursor positioning, mode setting), producing
	// visible artifacts like stray "[A" on the client.
	time.Sleep(80 * time.Millisecond)

	// ── Reset terminal state ──────────────────────────────────────────
	// RIS (\x1bc) resets the xterm.js state machine so history bytes are
	// interpreted against a clean slate. A short delay after RIS lets the
	// client process it before we stream history + live output.
	conn.WriteJSON(map[string]string{
		"type": "output",
		"data": "\x1bc",
	})

	// ── Capture scrollback history ────────────────────────────────────
	// Dump tmux pane history so the client can scroll back to content
	// from before this WebSocket connection.
	if out, err := exec.Command("tmux", "capture-pane", "-p", "-S", "-10000", "-e", "-t", session.TmuxName).Output(); err == nil && len(out) > 0 {
		conn.WriteJSON(map[string]string{
			"type": "history",
			"data": string(out),
		})
	}
	// Marker line so the user knows where the reconnect point is.
	conn.WriteJSON(map[string]string{
		"type": "output",
		"data": "\r\n\x1b[90m● " + time.Now().Format("15:04:05") + " — connected to " + session.TmuxName + "\x1b[0m\r\n",
	})

	// ── Send session list on connect ──────────────────────────────────
	listAndSendSessions(conn, session.TmuxName)

	// Start PTY reader goroutine — only AFTER history is sent, so the
	// first live bytes don't interleave with capture-pane output.
	done := startPTYReader(ptyFile, conn)
	// Snapshot for the main loop's select — updated on re-attach after detach.
	localDone := done

	// Main loop: read WebSocket messages → PTY
	for {
		select {
		case <-localDone:
			// PTY exited (tmux detach via prefix+d, or terminal exit).
			// Keep WebSocket alive so the client can list sessions, switch,
			// create new windows, or kill sessions without reconnecting.
			log.Printf("PTY exited (detach or exit)")
			if session.PTY != nil {
				session.PTY.Close()
				session.PTY = nil
			}
			session.Cmd = nil

			// Restore status bar on the detached session so other clients
			// (native Mac terminals) show normal tmux indicators again.
			if session.TmuxName != "" {
				exec.Command("tmux", "set-option", "-t", session.TmuxName, "status", "on").Run()
			}

			// Only send session_detached if TmuxName is known (not already
			// cleared by kill_session which also closes the PTY).
			if session.TmuxName != "" {
				conn.WriteJSON(map[string]interface{}{
					"type":    "session_detached",
					"session": session.TmuxName,
				})
			}

			// Reset the done channel — will be replaced when the client
			// sends switch_session or new_window to re-attach.
			done = make(chan struct{})
			localDone = done
			// Continue loop — WebSocket stays alive for session management.

		default:
		}

		_, msgBytes, err := conn.ReadMessage()
		if err != nil {
			log.Printf("WebSocket read error: %v", err)
			return
		}

		// Parse the message type
		var raw map[string]interface{}
		if err := json.Unmarshal(msgBytes, &raw); err != nil {
			log.Printf("Failed to parse message: %v", err)
			continue
		}

		msgType, _ := raw["type"].(string)
		switch msgType {
		case "ping":
			pong := map[string]string{"type": "pong"}
			if err := conn.WriteJSON(pong); err != nil {
				log.Printf("Failed to send pong: %v", err)
			}

		case "input":
			var msg InputMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse input message: %v", err)
				continue
			}
			if session.PTY != nil {
				if _, err := session.PTY.Write([]byte(msg.Data)); err != nil {
					log.Printf("PTY write error: %v", err)
				}
			}

		case "signal":
			var msg SignalMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse signal message: %v", err)
				continue
			}
			switch msg.Name {
			case "int":
				if session.Cmd != nil && session.Cmd.Process != nil {
					session.Cmd.Process.Signal(syscall.SIGINT)
				}
			case "eof":
				if session.PTY != nil {
					session.PTY.Write([]byte{0x04}) // Ctrl-D
				}
			}

		case "resize":
			var msg ResizeMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse resize message: %v", err)
				continue
			}
			log.Printf("Resize to %dx%d", msg.Cols, msg.Rows)
			if session.PTY != nil {
				if err := ResizePTY(session.PTY, msg.Rows, msg.Cols); err != nil {
					log.Printf("PTY resize error: %v", err)
				}
			}

		case "list_sessions":
			listAndSendSessions(conn)

		case "switch_session":
			var msg SwitchSessionMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse switch_session message: %v", err)
				continue
			}
			// Send RIS (Reset to Initial State) before switching sessions.
			// This resets SwiftTerm's state machine — alternate screen buffer,
			// cursor position, color attributes, character sets — so that the
			// new session's escape sequences are interpreted against a clean
			// terminal state instead of stale state from the old session.
			conn.WriteJSON(map[string]string{
				"type": "output",
				"data": "\x1bc\x1b[2J\x1b[H",
			})

			oldTmuxName := session.TmuxName

			if session.PTY != nil {
				// Attached — use tmux switch-client with the bridge's client
				// name so we never hijack a Mac-native tmux client via $TMUX.
				args := []string{"switch-client", "-t", msg.SessionName}
				if session.ClientName != "" {
					args = append(args, "-c", session.ClientName)
				}
				switchCmd := exec.Command("tmux", args...)
				if out, err := switchCmd.CombinedOutput(); err != nil {
					log.Printf("switch-client failed: %s", string(out))
					conn.WriteJSON(map[string]interface{}{
						"type":    "error",
						"message": fmt.Sprintf("Failed to switch: %v", err),
					})
					continue
				}
			} else {
				// Detached — check that the session still exists before attaching.
				// If it was killed externally (e.g. from Mac), don't silently
				// recreate it — return an error so the phone refreshes its list.
				hasSession := exec.Command("tmux", "has-session", "-t", msg.SessionName)
				if hasSession.Run() != nil {
					log.Printf("Session %s not found — may have been killed externally", msg.SessionName)
					conn.WriteJSON(map[string]interface{}{
						"type":    "error",
						"message": fmt.Sprintf("Session '%s' no longer exists", msg.SessionName),
					})
					// Also send a refreshed session list so the client can update.
					listAndSendSessions(conn)
					continue
				}
				// Start a new PTY attachment to the target session.
				_, ptyFile, cmd, clientName, err := startTmuxSession(msg.SessionName)
				if err != nil {
					log.Printf("Failed to attach to session %s: %v", msg.SessionName, err)
					conn.WriteJSON(map[string]interface{}{
						"type":    "error",
						"message": fmt.Sprintf("Failed to attach: %v", err),
					})
					continue
				}
				session.PTY = ptyFile
				session.Cmd = cmd
				session.ClientName = clientName
				session.Active = true
				// Start a new PTY reader goroutine with a fresh done channel.
				done = startPTYReader(ptyFile, conn)
				localDone = done
				log.Printf("Re-attached to tmux session: %s (client: %s)", msg.SessionName, clientName)
			}

			// Toggle status: off on the new session (phone view), on on the old
			// session so Mac terminals show normal tmux indicators.
			if oldTmuxName != "" && oldTmuxName != msg.SessionName {
				exec.Command("tmux", "set-option", "-t", oldTmuxName, "status", "on").Run()
			}
			exec.Command("tmux", "set-option", "-t", msg.SessionName, "status", "off").Run()

			session.TmuxName = msg.SessionName
			conn.WriteJSON(map[string]interface{}{
				"type":    "session_switched",
				"session": msg.SessionName,
			})

		case "new_window":
			var msg NewWindowMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse new_window message: %v", err)
				continue
			}
			// Create a new tmux session starting in the user's home directory.
			homeDir, _ := os.UserHomeDir()
			if homeDir == "" {
				homeDir = os.Getenv("HOME")
			}
			create := exec.Command("tmux", "new-session", "-d", "-s", msg.SessionName, "-c", homeDir)
			if out, err := create.CombinedOutput(); err != nil {
				log.Printf("new-session failed: %s", string(out))
				conn.WriteJSON(map[string]interface{}{
					"type":    "error",
					"message": fmt.Sprintf("Failed to create session: %v", err),
				})
				continue
			}
			// Send RIS so the terminal resets before showing the new session.
			conn.WriteJSON(map[string]string{
				"type": "output",
				"data": "\x1bc\x1b[2J\x1b[H",
			})

			oldTmuxName := session.TmuxName

			if session.PTY != nil {
				// Attached — switch via bridge client so we don't hijack Mac's tmux.
				args := []string{"switch-client", "-t", msg.SessionName}
				if session.ClientName != "" {
					args = append(args, "-c", session.ClientName)
				}
				exec.Command("tmux", args...).Run()
			} else {
				// Detached — start a new PTY attachment to the newly created session.
				_, ptyFile, cmd, clientName, err := startTmuxSession(msg.SessionName)
				if err != nil {
					log.Printf("Failed to attach to new session %s: %v", msg.SessionName, err)
					conn.WriteJSON(map[string]interface{}{
						"type":    "error",
						"message": fmt.Sprintf("Failed to attach: %v", err),
					})
					continue
				}
				session.PTY = ptyFile
				session.Cmd = cmd
				session.ClientName = clientName
				session.Active = true
				done = startPTYReader(ptyFile, conn)
				localDone = done
				log.Printf("Attached to new tmux session: %s (client: %s)", msg.SessionName, clientName)
			}
			// Toggle status: off on the new session (phone view), on on the old.
			if oldTmuxName != "" && oldTmuxName != msg.SessionName {
				exec.Command("tmux", "set-option", "-t", oldTmuxName, "status", "on").Run()
			}
			exec.Command("tmux", "set-option", "-t", msg.SessionName, "status", "off").Run()

			session.TmuxName = msg.SessionName

			log.Printf("Created new tmux session: %s (cwd: %s)", msg.SessionName, homeDir)
			conn.WriteJSON(map[string]interface{}{
				"type":    "session_created",
				"session": msg.SessionName,
			})

		case "select_window":
			var msg SelectWindowMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse select_window message: %v", err)
				continue
			}
			direction := msg.Direction
			if direction != "next" && direction != "prev" {
				conn.WriteJSON(map[string]interface{}{
					"type":    "error",
					"message": fmt.Sprintf("Invalid direction: %s (must be 'next' or 'prev')", direction),
				})
				continue
			}
			cmd := exec.Command("tmux", "select-window", fmt.Sprintf("-t:%s", direction))
			if err := cmd.Run(); err != nil {
				conn.WriteJSON(map[string]interface{}{
					"type":    "error",
					"message": fmt.Sprintf("Failed to select window: %v", err),
				})
				continue
			}
			conn.WriteJSON(map[string]interface{}{
				"type":      "window_selected",
				"direction": direction,
			})

		case "kill_session":
			var msg KillSessionMessage
			if err := json.Unmarshal(msgBytes, &msg); err != nil {
				log.Printf("Failed to parse kill_session message: %v", err)
				continue
			}
			killCmd := exec.Command("tmux", "kill-session", "-t", msg.SessionName)
			if out, err := killCmd.CombinedOutput(); err != nil {
				log.Printf("kill-session failed: %s", string(out))
				conn.WriteJSON(map[string]interface{}{
					"type":    "error",
					"message": fmt.Sprintf("Failed to kill session: %v", err),
				})
				continue
			}
			log.Printf("Killed tmux session: %s", msg.SessionName)
			// Restore status bar before killing so other clients (Mac terminals)
			// don't get a stale "status off" on this session's pane.
			exec.Command("tmux", "set-option", "-t", msg.SessionName, "status", "on").Run()

			// If we killed the currently attached session, clean up the PTY.
			// Clear TmuxName BEFORE closing PTY so the detach handler below
			// doesn't send a stale session_detached with the now-dead session.
			if msg.SessionName == session.TmuxName {
				session.TmuxName = ""
				session.ClientName = ""
				if session.PTY != nil {
					session.PTY.Close()
					session.PTY = nil
				}
				session.Cmd = nil
			}
			conn.WriteJSON(map[string]interface{}{
				"type":    "session_killed",
				"session": msg.SessionName,
			})
			// Send the updated session list to the client.
			listAndSendSessions(conn)

		default:
			log.Printf("Unknown message type: %s", msgType)
		}
	}
}

// getOrCreateSession returns the default session, creating one if needed.
func getOrCreateSession() *Session {
	sessions := ListSessions()
	if len(sessions) > 0 {
		sess, err := GetSession(sessions[0].ID)
		if err == nil {
			return sess
		}
	}
	return NewSession("claude-code")
}

// Start starts the HTTP + WebSocket server on the given address.
func Start(addr string) error {
	// Embedded static frontend (PWA)
	staticFS, _ := fs.Sub(webFS, "web")

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", handleWebSocket)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("Health check from: %s", r.RemoteAddr)
		w.Header().Set("Content-Type", "text/plain")
		w.WriteHeader(200)
		fmt.Fprintf(w, "ok\n")
	})
	mux.Handle("/", http.FileServer(http.FS(staticFS)))

	// Log every incoming HTTP request at the connection level
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("HTTP %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)
		mux.ServeHTTP(w, r)
	})

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %w", addr, err)
	}
	log.Printf("Listening on %s", addr)

	srv := &http.Server{Handler: handler}
	go func() {
		if err := srv.Serve(ln); err != nil && err != http.ErrServerClosed {
			log.Printf("HTTP server error: %v", err)
		}
	}()

	return nil
}
