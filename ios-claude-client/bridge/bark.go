package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
)

// BarkConfig holds the configuration loaded from ~/.config/bark/bark.env.
type BarkConfig struct {
	Server    string
	DeviceKey string
	Group     string
}

// BarkRequest is the JSON body accepted by POST /bark.
type BarkRequest struct {
	Title string `json:"title"`
	Body  string `json:"body"`
	Level string `json:"level"`
	Group string `json:"group"`
}

// loadBarkConfig reads Bark configuration from the standard config file.
func loadBarkConfig() (*BarkConfig, error) {
	cfg := &BarkConfig{
		Server: "https://api.day.app",
		Group:  "Mac",
	}

	// Try reading the config file via shell source (simplest way to parse env
	// vars without reimplementing shell parsing in Go).
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("cannot determine home directory: %w", err)
	}
	configFile := os.Getenv("BARK_CONFIG")
	if configFile == "" {
		configFile = home + "/.config/bark/bark.env"
	}

	// Use a subprocess to source the file and print values. This is the safest
	// way to parse the shell-quoted values stored by the `bark` CLI.
	out, err := exec.Command("bash", "-c",
		fmt.Sprintf("source '%s' 2>/dev/null; echo \"server=$BARK_SERVER\"; echo \"key=$BARK_DEVICE_KEY\"; echo \"group=$BARK_GROUP\"", configFile),
	).Output()
	if err != nil || len(out) == 0 {
		return nil, fmt.Errorf("failed to read Bark config from %s", configFile)
	}

	// Parse the key=value output
	for _, line := range splitLines(string(out)) {
		switch {
		case len(line) > 7 && line[:7] == "server=":
			cfg.Server = line[7:]
		case len(line) > 4 && line[:4] == "key=":
			cfg.DeviceKey = line[4:]
		case len(line) > 6 && line[:6] == "group=":
			cfg.Group = line[6:]
		}
	}

	if cfg.DeviceKey == "" {
		return nil, fmt.Errorf("BARK_DEVICE_KEY not configured")
	}

	return cfg, nil
}

// sendBarkPush sends a push notification via the Bark API.
func sendBarkPush(cfg *BarkConfig, title, body, level, group string) error {
	endpoint := cfg.Server
	if endpoint[len(endpoint)-1] == '/' {
		endpoint = endpoint[:len(endpoint)-1]
	}
	endpoint += "/push"

	form := url.Values{}
	form.Set("device_key", cfg.DeviceKey)
	form.Set("title", title)
	form.Set("body", body)
	if level != "" {
		form.Set("level", level)
	} else {
		form.Set("level", "active")
	}
	if group != "" {
		form.Set("group", group)
	} else {
		form.Set("group", cfg.Group)
	}

	resp, err := http.PostForm(endpoint, form)
	if err != nil {
		return fmt.Errorf("failed to POST bark API: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("bark API returned HTTP %d", resp.StatusCode)
	}

	return nil
}

// handleBarkPush handles POST /bark — forward a notification.
func handleBarkPush(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req BarkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("invalid JSON: %v", err), http.StatusBadRequest)
		return
	}

	if req.Title == "" {
		http.Error(w, "missing required field: title", http.StatusBadRequest)
		return
	}

	cfg, err := loadBarkConfig()
	if err != nil {
		log.Printf("Bark config load failed: %v", err)
		http.Error(w, fmt.Sprintf("Bark not configured: %v", err), http.StatusServiceUnavailable)
		return
	}

	if err := sendBarkPush(cfg, req.Title, req.Body, req.Level, req.Group); err != nil {
		log.Printf("Bark push failed: %v", err)
		http.Error(w, fmt.Sprintf("push failed: %v", err), http.StatusInternalServerError)
		return
	}

	log.Printf("Bark notification sent: title=%q", req.Title)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "sent"})
}

// handleBarkHealth handles GET /bark/health — check if Bark is configured.
func handleBarkHealth(w http.ResponseWriter, r *http.Request) {
	cfg, err := loadBarkConfig()
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK) // Still 200 — service is alive
		json.NewEncoder(w).Encode(map[string]interface{}{
			"bark_available": false,
			"reason":         err.Error(),
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"bark_available": true,
		"server":         cfg.Server,
		"group":          cfg.Group,
	})
}

// splitLines splits a string by newline, handling \n and \r\n.
func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		} else if s[i] == '\r' && i+1 < len(s) && s[i+1] == '\n' {
			lines = append(lines, s[start:i])
			start = i + 2
			i++
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}
