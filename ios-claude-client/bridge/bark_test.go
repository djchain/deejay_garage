package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// writeTempBarkConfig creates a temporary bark config file with the given
// values and sets BARK_CONFIG to point to it. Returns a cleanup function.
func writeTempBarkConfig(t *testing.T, deviceKey string) func() {
	t.Helper()

	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "bark.env")

	content := "BARK_SERVER='https://api.day.app'\n"
	content += "BARK_DEVICE_KEY='" + deviceKey + "'\n"
	content += "BARK_GROUP='Test'\n"

	err := os.WriteFile(configPath, []byte(content), 0600)
	require.NoError(t, err)

	oldVal := os.Getenv("BARK_CONFIG")
	os.Setenv("BARK_CONFIG", configPath)

	return func() {
		os.Setenv("BARK_CONFIG", oldVal)
	}
}

// TestBarkHealthConfigured verifies /bark/health returns bark_available=true
// when a valid config exists.
func TestBarkHealthConfigured(t *testing.T) {
	cleanup := writeTempBarkConfig(t, "test-key-123")
	defer cleanup()

	req := httptest.NewRequest(http.MethodGet, "/bark/health", nil)
	w := httptest.NewRecorder()

	handleBarkHealth(w, req)

	assert.Equal(t, http.StatusOK, w.Code)

	var resp map[string]interface{}
	err := json.NewDecoder(w.Body).Decode(&resp)
	require.NoError(t, err)

	assert.Equal(t, true, resp["bark_available"])
	assert.Equal(t, "https://api.day.app", resp["server"])
	assert.Equal(t, "Test", resp["group"])
}

// TestBarkHealthUnconfigured verifies /bark/health returns bark_available=false
// when no valid config exists.
func TestBarkHealthUnconfigured(t *testing.T) {
	oldVal := os.Getenv("BARK_CONFIG")
	os.Setenv("BARK_CONFIG", "/nonexistent/bark.env")
	defer os.Setenv("BARK_CONFIG", oldVal)

	req := httptest.NewRequest(http.MethodGet, "/bark/health", nil)
	w := httptest.NewRecorder()

	handleBarkHealth(w, req)

	assert.Equal(t, http.StatusOK, w.Code) // Service itself is alive

	var resp map[string]interface{}
	err := json.NewDecoder(w.Body).Decode(&resp)
	require.NoError(t, err)

	assert.Equal(t, false, resp["bark_available"])
}

// TestBarkPushMissingTitle verifies POST /bark returns 400 when title is empty.
func TestBarkPushMissingTitle(t *testing.T) {
	body := bytes.NewBufferString(`{"body":"test body"}`)
	req := httptest.NewRequest(http.MethodPost, "/bark", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleBarkPush(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}

// TestBarkPushInvalidJSON verifies POST /bark returns 400 for malformed JSON.
func TestBarkPushInvalidJSON(t *testing.T) {
	body := bytes.NewBufferString(`not json at all`)
	req := httptest.NewRequest(http.MethodPost, "/bark", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleBarkPush(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
}

// TestBarkPushMethodNotAllowed verifies POST /bark only accepts POST.
func TestBarkPushMethodNotAllowed(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/bark", nil)
	w := httptest.NewRecorder()

	handleBarkPush(w, req)

	assert.Equal(t, http.StatusMethodNotAllowed, w.Code)
}

// TestBarkPushValidJSONStructure verifies POST /bark accepts valid JSON
// structure (title, body, level, group) and parses it correctly.
func TestBarkPushValidJSONStructure(t *testing.T) {
	cleanup := writeTempBarkConfig(t, "test-key-struct")
	defer cleanup()

	reqBody := BarkRequest{
		Title: "Test Title",
		Body:  "Test body content",
		Level: "active",
		Group: "TestGroup",
	}
	var buf bytes.Buffer
	err := json.NewEncoder(&buf).Encode(reqBody)
	require.NoError(t, err)

	req := httptest.NewRequest(http.MethodPost, "/bark", &buf)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleBarkPush(w, req)

	// The actual push to api.day.app will likely fail in test (no network),
	// but the handler should attempt it and return the error.
	// We verify: it parsed the JSON, loaded config, attempted the push.
	assert.NotEqual(t, http.StatusBadRequest, w.Code,
		"should not be a bad request (JSON is valid)")
	assert.NotEqual(t, http.StatusMethodNotAllowed, w.Code,
		"should not reject HTTP method")
}

// TestBarkPushUnconfigured verifies POST /bark returns 503 when Bark config
// is missing.
func TestBarkPushUnconfigured(t *testing.T) {
	oldVal := os.Getenv("BARK_CONFIG")
	os.Setenv("BARK_CONFIG", "/nonexistent/bark.env")
	defer os.Setenv("BARK_CONFIG", oldVal)

	reqBody := BarkRequest{Title: "Test", Body: "Test"}
	var buf bytes.Buffer
	json.NewEncoder(&buf).Encode(reqBody)

	req := httptest.NewRequest(http.MethodPost, "/bark", &buf)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	handleBarkPush(w, req)

	assert.Equal(t, http.StatusServiceUnavailable, w.Code)
}

// TestSplitLines verifies the helper function for parsing config output.
func TestSplitLines(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []string
	}{
		{
			name:     "unix newlines",
			input:    "server=foo\nkey=bar\ngroup=baz\n",
			expected: []string{"server=foo", "key=bar", "group=baz"},
		},
		{
			name:     "empty string",
			input:    "",
			expected: nil,
		},
		{
			name:     "single line",
			input:    "hello",
			expected: []string{"hello"},
		},
		{
			name:     "trailing newline",
			input:    "line1\nline2\n",
			expected: []string{"line1", "line2"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := splitLines(tt.input)
			assert.Equal(t, tt.expected, got)
		})
	}
}

// TestLoadBarkConfig_Valid verifies config loading from a temp file.
func TestLoadBarkConfig_Valid(t *testing.T) {
	cleanup := writeTempBarkConfig(t, "my-device-key-abc")
	defer cleanup()

	cfg, err := loadBarkConfig()
	require.NoError(t, err)
	assert.Equal(t, "my-device-key-abc", cfg.DeviceKey)
	assert.Equal(t, "https://api.day.app", cfg.Server)
	assert.Equal(t, "Test", cfg.Group)
}

// TestLoadBarkConfig_MissingDeviceKey verifies error when key is empty.
func TestLoadBarkConfig_MissingDeviceKey(t *testing.T) {
	cleanup := writeTempBarkConfig(t, "") // empty key
	defer cleanup()

	_, err := loadBarkConfig()
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "BARK_DEVICE_KEY")
}

// TestLoadBarkConfig_NonexistentFile verifies error when config file doesn't exist.
func TestLoadBarkConfig_NonexistentFile(t *testing.T) {
	oldVal := os.Getenv("BARK_CONFIG")
	os.Setenv("BARK_CONFIG", "/nonexistent/path/bark.env")
	defer os.Setenv("BARK_CONFIG", oldVal)

	_, err := loadBarkConfig()
	assert.Error(t, err)
}
