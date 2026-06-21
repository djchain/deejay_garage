package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/hashicorp/mdns"
)

var mdnsServer *mdns.Server

// Register registers a Bonjour/mDNS service on the network.
func Register(name string, port int) error {
	host, err := os.Hostname()
	if err != nil {
		return fmt.Errorf("failed to get hostname: %w", err)
	}
	host = normalizeFQDN(host)

	service, err := mdns.NewMDNSService(
		name,
		"_claudebridge._tcp",
		"",
		host,
		port,
		nil,
		[]string{"version=v1.0.0"},
	)
	if err != nil {
		return fmt.Errorf("failed to create mDNS service: %w", err)
	}

	server, err := mdns.NewServer(&mdns.Config{Zone: service})
	if err != nil {
		return fmt.Errorf("failed to start mDNS server: %w", err)
	}

	mdnsServer = server
	return nil
}

// Deregister removes the previously registered mDNS service.
func Deregister() error {
	if mdnsServer != nil {
		mdnsServer.Shutdown()
		mdnsServer = nil
	}
	return nil
}

func normalizeFQDN(host string) string {
	host = strings.TrimSpace(host)
	if host == "" || strings.HasSuffix(host, ".") {
		return host
	}
	return host + "."
}
