package main

import (
	"fmt"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Session represents a terminal session that can be bridged to a WebSocket client.
type Session struct {
	ID         string
	Name       string
	TmuxName   string
	ClientName string // tmux client name (e.g. /dev/ttys005) tied to the bridge PTY
	PTY        *os.File
	Cmd        *exec.Cmd
	CreatedAt  time.Time
	LastUsed   time.Time
	Active     bool
}

var (
	sessionsMu sync.RWMutex
	sessions   = make(map[string]*Session)
)

// NewSession creates a new session with a unique ID and stores it.
func NewSession(name string) *Session {
	now := time.Now()
	s := &Session{
		ID:        uuid.New().String(),
		Name:      name,
		Active:    true,
		CreatedAt: now,
		LastUsed:  now,
	}

	sessionsMu.Lock()
	sessions[s.ID] = s
	sessionsMu.Unlock()

	return s
}

// GetSession retrieves a session by its ID.
func GetSession(id string) (*Session, error) {
	sessionsMu.RLock()
	s, ok := sessions[id]
	sessionsMu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("session %s not found", id)
	}
	return s, nil
}

// ListSessions returns all active sessions.
func ListSessions() []*Session {
	sessionsMu.RLock()
	result := make([]*Session, 0, len(sessions))
	for _, s := range sessions {
		result = append(result, s)
	}
	sessionsMu.RUnlock()
	return result
}

// DeleteSession removes a session by its ID.
func DeleteSession(id string) error {
	sessionsMu.Lock()
	_, ok := sessions[id]
	if !ok {
		sessionsMu.Unlock()
		return fmt.Errorf("session %s not found", id)
	}
	delete(sessions, id)
	sessionsMu.Unlock()
	return nil
}
