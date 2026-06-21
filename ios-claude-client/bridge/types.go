package main

import (
	"encoding/json"
	"fmt"
)

// InputMessage represents an input keystroke message from the client.
type InputMessage struct {
	Type string `json:"type"`
	Data string `json:"data"`
}

// UnmarshalJSON validates that the message has a non-empty type field.
func (m *InputMessage) UnmarshalJSON(data []byte) error {
	type inputMessageAlias InputMessage
	var alias inputMessageAlias
	if err := json.Unmarshal(data, &alias); err != nil {
		return err
	}
	if alias.Type == "" {
		return fmt.Errorf("missing required field 'type'")
	}
	*m = InputMessage(alias)
	return nil
}

// OutputMessage represents an output message sent to the client.
type OutputMessage struct {
	Type string `json:"type"`
	Data string `json:"data"`
}

// SignalMessage represents a control signal message (SIGINT, EOF).
type SignalMessage struct {
	Type string `json:"type"`
	Name string `json:"name"`
}

// PingMessage represents a ping message from the client.
type PingMessage struct {
	Type string `json:"type"`
}

// ResizeMessage represents a terminal resize message.
type ResizeMessage struct {
	Type string `json:"type"`
	Cols int    `json:"cols"`
	Rows int    `json:"rows"`
}

// ListSessionsMessage represents a request to list tmux sessions.
type ListSessionsMessage struct {
	Type string `json:"type"`
}

// SwitchSessionMessage represents a request to switch to a different tmux session.
type SwitchSessionMessage struct {
	Type        string `json:"type"`
	SessionName string `json:"sessionName"`
}

// NewWindowMessage represents a request to create a new window in a session.
type NewWindowMessage struct {
	Type        string `json:"type"`
	SessionName string `json:"sessionName"`
}

// SelectWindowMessage represents a request to select a window by direction.
type SelectWindowMessage struct {
	Type      string `json:"type"`
	Direction string `json:"direction"`
}

// KillSessionMessage represents a request to kill a tmux session.
type KillSessionMessage struct {
	Type        string `json:"type"`
	SessionName string `json:"sessionName"`
}

// SessionInfo represents information about a tmux session.
type SessionInfo struct {
	Name    string `json:"name"`
	Windows int    `json:"windows"`
}
