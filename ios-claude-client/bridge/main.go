package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	port := flag.String("port", "0.0.0.0:9090", "WebSocket server port (e.g. 0.0.0.0:9090)")
	sessionName := flag.String("session", "claude-code", "tmux session name")
	flag.Parse()

	log.Printf("Starting Claude Code Bridge...")
	log.Printf("Session: %s", *sessionName)
	log.Printf("Port: %s", *port)

	// Create a session with tmux name
	sess := NewSession(*sessionName)
	sess.TmuxName = *sessionName
	log.Printf("Session created: %s (tmux: %s)", sess.ID, sess.TmuxName)

	// Register Bonjour/mDNS service (best-effort)
	if err := Register("Claude Bridge", 9090); err != nil {
		log.Printf("Warning: mDNS registration failed: %v", err)
	} else {
		log.Println("mDNS service registered")
		defer Deregister()
	}

	// Start WebSocket server
	if err := Start(*port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
	log.Printf("Server listening on %s/ws", *port)

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigCh
	log.Printf("Received signal %v, shutting down...", sig)
}
