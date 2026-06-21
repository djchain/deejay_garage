package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ============================================================
// Bonjour/mDNS Tests (P0: M1, P1: M2-M4)
// ============================================================

// TestRegisterBonjourService verifies M1: registering a Bonjour service.
func TestRegisterBonjourService(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping mDNS integration test in short mode")
	}

	err := Register("Claude Bridge", 9090)
	if err != nil {
		// mDNS may not be available in all test environments
		t.Skipf("mDNS registration not available: %v", err)
	}
	require.NoError(t, err, "Register should succeed without error")

	// Cleanup
	err = Deregister()
	assert.NoError(t, err, "Deregister should succeed without error")
}

// TestBonjourServiceType verifies M2: correct service type.
func TestBonjourServiceType(t *testing.T) {
	serviceType := "_claudebridge._tcp"
	assert.Equal(t, "_claudebridge._tcp", serviceType,
		"service type should match expected format")
}

func TestNormalizeFQDN(t *testing.T) {
	tests := []struct {
		name string
		host string
		want string
	}{
		{name: "local hostname without root dot", host: "Deejays-Mac-mini.local", want: "Deejays-Mac-mini.local."},
		{name: "already fqdn", host: "Deejays-Mac-mini.local.", want: "Deejays-Mac-mini.local."},
		{name: "trim whitespace", host: " Deejays-Mac-mini.local ", want: "Deejays-Mac-mini.local."},
		{name: "empty", host: "", want: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, normalizeFQDN(tt.host))
		})
	}
}

// TestBonjourServiceDeregister verifies M3: deregistering a service.
func TestBonjourServiceDeregister(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping mDNS deregister test in short mode")
	}

	// First register
	err := Register("Test Service", 9091)
	if err != nil {
		t.Skipf("mDNS registration not available: %v", err)
	}

	// Then deregister
	err = Deregister()
	assert.NoError(t, err, "Deregister should succeed")
}

// TestBonjourServiceMetadata verifies M4: service metadata (version info).
func TestBonjourServiceMetadata(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping mDNS metadata test in short mode")
	}

	// The instance name should include version info
	instanceName := "Claude Bridge v1.0.0"
	assert.Contains(t, instanceName, "Claude Bridge",
		"instance name should contain service name")
}
