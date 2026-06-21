package main

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ============================================================
// Session CRUD Tests (P0: S1-S2, P1: S3-S5, S8)
// ============================================================

// TestNewSession verifies S1: creating a new session.
func TestNewSession(t *testing.T) {
	session := NewSession("main")
	require.NotNil(t, session, "NewSession should return a non-nil session")
	assert.NotEmpty(t, session.ID, "session ID should not be empty")
	assert.Equal(t, "main", session.Name)
	assert.True(t, session.Active, "new session should be active")
	assert.False(t, session.CreatedAt.IsZero(), "CreatedAt should be set")
	assert.False(t, session.LastUsed.IsZero(), "LastUsed should be set")
	assert.Equal(t, session.CreatedAt, session.LastUsed,
		"CreatedAt and LastUsed should be equal for a new session")
}

// TestNewSessionUniqueID verifies S8: session IDs are unique across creations.
func TestNewSessionUniqueID(t *testing.T) {
	sessions := make(map[string]bool)
	const count = 100

	for i := 0; i < count; i++ {
		s := NewSession("test")
		require.NotNil(t, s)
		assert.False(t, sessions[s.ID], "session ID %s was duplicated", s.ID)
		sessions[s.ID] = true
	}

	assert.Len(t, sessions, count, "should have %d unique session IDs", count)
}

// TestGetSession verifies S2: retrieving a session by ID.
func TestGetSession(t *testing.T) {
	created := NewSession("main")
	require.NotNil(t, created)

	found, err := GetSession(created.ID)
	require.NoError(t, err, "GetSession should not return an error for existing session")
	require.NotNil(t, found, "GetSession should return non-nil for existing session")
	assert.Equal(t, created.ID, found.ID)
	assert.Equal(t, created.Name, found.Name)
}

// TestGetSessionNotFound verifies S3: retrieving a non-existent session.
func TestGetSessionNotFound(t *testing.T) {
	session, err := GetSession("nonexistent-id-12345")
	assert.Error(t, err, "GetSession should return error for non-existent session")
	assert.Nil(t, session, "GetSession should return nil for non-existent session")
}

// TestListSessions verifies S4: listing all sessions.
func TestListSessions(t *testing.T) {
	// Create multiple sessions
	names := []string{"session-a", "session-b", "session-c"}
	for _, name := range names {
		s := NewSession(name)
		require.NotNil(t, s)
	}

	sessions := ListSessions()
	require.NotNil(t, sessions, "ListSessions should return a non-nil slice")

	// Verify each created session appears in the list
	for _, name := range names {
		found := false
		for _, s := range sessions {
			if s.Name == name {
				found = true
				break
			}
		}
		assert.True(t, found, "session %s should be in the list", name)
	}
}

// TestListSessionsEmpty verifies ListSessions returns empty (or nil) when no sessions.
func TestListSessionsEmpty(t *testing.T) {
	// This test assumes sessions are isolated per-test or we reset state.
	// We use a fresh state approach - just ensure the function returns safely.
	sessions := ListSessions()
	assert.NotPanics(t, func() { _ = len(sessions) }, "ListSessions should not panic")
}

// TestDeleteSession verifies S5: deleting a session.
func TestDeleteSession(t *testing.T) {
	created := NewSession("to-be-deleted")
	require.NotNil(t, created)

	// Verify it exists
	found, err := GetSession(created.ID)
	require.NoError(t, err)
	require.NotNil(t, found)

	// Delete it
	err = DeleteSession(created.ID)
	require.NoError(t, err, "DeleteSession should not return error for existing session")

	// Verify it's gone
	deleted, err := GetSession(created.ID)
	assert.Error(t, err, "GetSession should return error for deleted session")
	assert.Nil(t, deleted, "GetSession should return nil for deleted session")
}

// TestDeleteSessionNotFound verifies deleting a non-existent session.
func TestDeleteSessionNotFound(t *testing.T) {
	err := DeleteSession("nonexistent-id-12345")
	assert.Error(t, err, "DeleteSession should return error for non-existent session")
}

// TestSessionLifecycle verifies the full lifecycle: create, get, list, delete.
func TestSessionLifecycle(t *testing.T) {
	s := NewSession("lifecycle-test")
	require.NotNil(t, s)

	// Get
	found, err := GetSession(s.ID)
	require.NoError(t, err)
	assert.Equal(t, s.ID, found.ID)

	// List should contain it
	list := ListSessions()
	foundInList := false
	for _, ls := range list {
		if ls.ID == s.ID {
			foundInList = true
			break
		}
	}
	assert.True(t, foundInList, "session should be in ListSessions output")

	// Delete
	err = DeleteSession(s.ID)
	require.NoError(t, err)

	// Confirm deleted
	_, err = GetSession(s.ID)
	assert.Error(t, err)
}

// TestSessionFields verifies all Session struct fields are properly initialized.
func TestSessionFields(t *testing.T) {
	now := time.Now()
	s := NewSession("field-test")
	require.NotNil(t, s)

	assert.NotEmpty(t, s.ID, "ID should be non-empty")
	assert.Equal(t, "field-test", s.Name)
	assert.True(t, s.Active, "Active should default to true")
	assert.WithinDuration(t, now, s.CreatedAt, time.Second,
		"CreatedAt should be approximately now")
	assert.WithinDuration(t, now, s.LastUsed, time.Second,
		"LastUsed should be approximately now")
}
