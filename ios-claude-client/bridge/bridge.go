package main

import (
	"fmt"
	"os"
	"os/exec"
	"sync"

	"github.com/gorilla/websocket"
)

// Bridge states.
const (
	StateDisconnected = iota
	StateConnected
	StateBridging
)

// Bridge manages the WebSocket to PTY bridge state machine.
type Bridge struct {
	mu    sync.RWMutex
	state int
	conn  *websocket.Conn
	pty   *os.File
	cmd   *exec.Cmd
}

// NewBridge creates a new bridge in the Disconnected state.
func NewBridge() *Bridge {
	return &Bridge{
		state: StateDisconnected,
	}
}

// State returns the current bridge state.
func (b *Bridge) State() int {
	b.mu.RLock()
	defer b.mu.RUnlock()
	return b.state
}

// Connect transitions the bridge from Disconnected to Connected.
func (b *Bridge) Connect() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.state != StateDisconnected {
		return fmt.Errorf("cannot connect from state %d", b.state)
	}

	b.state = StateConnected
	return nil
}

// Disconnect transitions the bridge to Disconnected from any state.
func (b *Bridge) Disconnect() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	b.state = StateDisconnected
	return nil
}

// StartBridging transitions the bridge from Connected to Bridging.
func (b *Bridge) StartBridging() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.state != StateConnected {
		return fmt.Errorf("cannot start bridging from state %d", b.state)
	}

	b.state = StateBridging
	return nil
}
