import Foundation

// MARK: - SessionStore

final class SessionStore: ObservableObject {

    // MARK: Published Properties

    @Published var sessions: [SessionInfo] = []

    // MARK: Private Properties

    private let userDefaultsKey = "claude_remote_sessions"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Initialization

    init() {
        loadFromDefaults()
    }

    // MARK: - Public CRUD API

    /// Adds a new session and persists to UserDefaults.
    func add(_ session: SessionInfo) {
        // Avoid duplicates by checking host+port
        if let existingIndex = sessions.firstIndex(where: { $0.host == session.host && $0.port == session.port }) {
            var updated = sessions[existingIndex]
            updated.name = session.name
            updated.lastUsed = Date()
            sessions[existingIndex] = updated
        } else {
            sessions.append(session)
        }
        sortByLastUsed()
        saveToDefaults()
    }

    /// Removes a session by its identifier.
    func remove(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        saveToDefaults()
    }

    /// Updates an existing session's metadata.
    func update(_ session: SessionInfo) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
        sortByLastUsed()
        saveToDefaults()
    }

    /// Refreshes the `lastUsed` timestamp for a session.
    func touch(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var session = sessions[index]
        session.lastUsed = Date()
        sessions[index] = session
        sortByLastUsed()
        saveToDefaults()
    }

    // MARK: - Private Persistence

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            sessions = []
            return
        }
        do {
            sessions = try decoder.decode([SessionInfo].self, from: data)
            sortByLastUsed()
        } catch {
            print("[SessionStore] Failed to decode sessions: \(error)")
            sessions = []
        }
    }

    private func saveToDefaults() {
        do {
            let data = try encoder.encode(sessions)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("[SessionStore] Failed to encode sessions: \(error)")
        }
    }

    private func sortByLastUsed() {
        sessions.sort { $0.lastUsed > $1.lastUsed }
    }
}
