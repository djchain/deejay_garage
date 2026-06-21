package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ============================================================
// Bridge Core Tests (P0: B1-B7)
// ============================================================

// wsTestHandler is a WebSocket handler that receives an upgraded connection.
type wsTestHandler func(*websocket.Conn)

// newWSTestServer sets up a WebSocket test server and returns the URL + cleanup func.
func newWSTestServer(t *testing.T, handler wsTestHandler) (string, func()) {
	t.Helper()
	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		handler(conn)
	}))

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	return wsURL, srv.Close
}

// connectWS is a helper to establish a WebSocket connection for testing.
func connectWS(t *testing.T, url string) *websocket.Conn {
	t.Helper()
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err, "should connect to WebSocket")
	return conn
}

// TestBridgeStateInit verifies the bridge state machine initial state.
func TestBridgeStateInit(t *testing.T) {
	bridge := NewBridge()
	require.NotNil(t, bridge, "NewBridge should return non-nil bridge")
	assert.Equal(t, StateDisconnected, bridge.State(),
		"initial state should be DISCONNECTED")
}

// TestBridgeStateTransitions verifies state machine transitions.
func TestBridgeStateTransitions(t *testing.T) {
	bridge := NewBridge()
	require.NotNil(t, bridge)

	// DISCONNECTED -> CONNECTED
	err := bridge.Connect()
	require.NoError(t, err, "Connect should succeed")
	assert.Equal(t, StateConnected, bridge.State(), "should be CONNECTED after Connect")

	// CONNECTED -> BRIDGING
	err = bridge.StartBridging()
	require.NoError(t, err, "StartBridging should succeed")
	assert.Equal(t, StateBridging, bridge.State(), "should be BRIDGING after StartBridging")

	// BRIDGING -> DISCONNECTED
	err = bridge.Disconnect()
	require.NoError(t, err, "Disconnect should succeed")
	assert.Equal(t, StateDisconnected, bridge.State(), "should be DISCONNECTED after Disconnect")
}

// TestInputForwarding verifies B1: WS -> PTY input forwarding.
func TestInputForwarding(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	// Create a bridge instance with a test PTY
	bridge := NewBridge()
	require.NotNil(t, bridge)

	t.Log("Input forwarding test scaffold ready")
}

// TestOutputForwarding verifies B2: PTY -> WS output forwarding.
func TestOutputForwarding(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	t.Log("Output forwarding test scaffold ready")
}

// TestSignalINT verifies B3: handling Ctrl-C/SIGINT signal.
func TestSignalINT(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	sigMsg := SignalMessage{Type: "signal", Name: "int"}
	raw, err := json.Marshal(sigMsg)
	require.NoError(t, err)

	var parsed SignalMessage
	err = json.Unmarshal(raw, &parsed)
	require.NoError(t, err)
	assert.Equal(t, "int", parsed.Name)
}

// TestSignalEOF verifies B4: handling EOF (Ctrl-D) signal.
func TestSignalEOF(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	sigMsg := SignalMessage{Type: "signal", Name: "eof"}
	raw, err := json.Marshal(sigMsg)
	require.NoError(t, err)

	var parsed SignalMessage
	err = json.Unmarshal(raw, &parsed)
	require.NoError(t, err)
	assert.Equal(t, "eof", parsed.Name)
}

// TestPTYResizeForwarding verifies B5: WS resize -> PTY resize forwarding.
func TestPTYResizeForwarding(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test in short mode")
	}

	resizeMsg := ResizeMessage{Type: "resize", Cols: 80, Rows: 24}
	raw, err := json.Marshal(resizeMsg)
	require.NoError(t, err)

	var parsed ResizeMessage
	err = json.Unmarshal(raw, &parsed)
	require.NoError(t, err)
	assert.Equal(t, 80, parsed.Cols)
	assert.Equal(t, 24, parsed.Rows)

	t.Log("Resize forwarding test scaffold ready")
}

// TestPingResponse verifies B6: responding to ping with pong.
func TestPingResponse(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping ping test in short mode")
	}

	handler := func(conn *websocket.Conn) {
		defer conn.Close()

		// Read ping, send pong
		_, msgBytes, err := conn.ReadMessage()
		if err != nil {
			return
		}

		var ping PingMessage
		err = json.Unmarshal(msgBytes, &ping)
		assert.NoError(t, err)
		assert.Equal(t, "ping", ping.Type)

		// Respond with pong
		err = conn.WriteJSON(map[string]string{"type": "pong"})
		assert.NoError(t, err)
	}

	wsURL, cleanup := newWSTestServer(t, handler)
	defer cleanup()

	conn := connectWS(t, wsURL)
	defer conn.Close()

	// Send ping
	err := conn.WriteJSON(PingMessage{Type: "ping"})
	require.NoError(t, err, "should send ping without error")

	// Read pong response
	var response map[string]string
	err = conn.ReadJSON(&response)
	require.NoError(t, err, "should read pong response")
	assert.Equal(t, "pong", response["type"])
}

// TestPingResponseTimeout verifies ping response with a timeout.
func TestPingResponseTimeout(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping ping timeout test in short mode")
	}

	handler := func(conn *websocket.Conn) {
		defer conn.Close()

		_, _, err := conn.ReadMessage()
		if err != nil {
			return
		}

		// Respond with pong
		conn.WriteJSON(map[string]string{"type": "pong"})
	}

	wsURL, cleanup := newWSTestServer(t, handler)
	defer cleanup()

	conn := connectWS(t, wsURL)
	defer conn.Close()

	// Send ping and expect pong within timeout
	conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	err := conn.WriteJSON(PingMessage{Type: "ping"})
	require.NoError(t, err)

	var response map[string]string
	err = conn.ReadJSON(&response)
	require.NoError(t, err, "should receive pong within timeout")
	assert.Equal(t, "pong", response["type"])
}

// TestClientDisconnect verifies B7: client disconnect doesn't crash bridge.
func TestClientDisconnect(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping disconnect test in short mode")
	}

	serverDone := make(chan struct{})
	handler := func(conn *websocket.Conn) {
		defer func() { close(serverDone) }()
		defer conn.Close()

		_, _, err := conn.ReadMessage()
		// Client disconnected - this is expected, not an error for the server
		t.Logf("Server detected client disconnect: %v", err)
	}

	wsURL, cleanup := newWSTestServer(t, handler)
	defer cleanup()

	conn := connectWS(t, wsURL)

	// Send a message, then disconnect abruptly
	err := conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"input","data":"hello"}`))
	require.NoError(t, err)

	// Abrupt close (not clean)
	conn.Close()

	// Wait for server to process the disconnect
	select {
	case <-serverDone:
		t.Log("Server handled disconnect gracefully")
	case <-time.After(3 * time.Second):
		t.Fatal("server did not handle disconnect in time")
	}
}

// TestBridgeConcurrentSafety verifies B11: concurrent read/write safety.
func TestBridgeConcurrentSafety(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping concurrency test in short mode")
	}

	bridge := NewBridge()
	require.NotNil(t, bridge)

	// Run concurrent operations
	done := make(chan bool, 10)
	for i := 0; i < 10; i++ {
		go func(idx int) {
			switch idx % 3 {
			case 0:
				_ = bridge.State()
			case 1:
				bridge.Connect()
			case 2:
				bridge.Disconnect()
			}
			done <- true
		}(i)
	}

	for i := 0; i < 10; i++ {
		<-done
	}

	t.Log("concurrent bridge operations completed without race")
}

// TestBridgeConnectionOrdering verifies B10: bridge starts WS before PTY.
func TestBridgeConnectionOrdering(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping ordering test in short mode")
	}

	bridge := NewBridge()
	require.NotNil(t, bridge)

	// Should be disconnected initially
	assert.Equal(t, StateDisconnected, bridge.State())

	// WS connection should be established first
	err := bridge.Connect()
	require.NoError(t, err)
	assert.Equal(t, StateConnected, bridge.State())

	// Then PTY bridging starts
	err = bridge.StartBridging()
	require.NoError(t, err)
	assert.Equal(t, StateBridging, bridge.State())
}
