import SwiftUI

// MARK: - SessionListView
// Layer 2: Tmux session selection page.
// Monochrome minimalist — pure black & white, no colors.

struct SessionListView: View {

    let onOpen: () -> Void
    let onDisconnect: () -> Void

    @EnvironmentObject var viewModel: TerminalViewModel

    // MARK: Local State

    @State private var isLoading: Bool = false
    @State private var showNewSessionSheet: Bool = false
    @State private var newSessionName: String = ""
    @State private var selectedSession: TmuxSessionInfo?
    @State private var showConfirmSwitch: Bool = false
    @State private var sessionToDelete: TmuxSessionInfo?
    @State private var showConfirmDelete: Bool = false
    /// Prevents onDisconnect() from being called twice when user taps Disconnect button.
    @State private var disconnectRequested: Bool = false

    private var sessions: [TmuxSessionInfo] { viewModel.connectionManager.tmuxSessions }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            // Connection status bar (compact)
            connectionBar

            // Session list
            if sessions.isEmpty && !isLoading {
                emptyStateView
            } else {
                sessionList
            }
            bottomBar
        }
        .background(Color(white: 0.04).ignoresSafeArea())
        .onAppear {
            // Only show loading if we have no cached sessions
            if sessions.isEmpty {
                requestSessionList()
            } else {
                // Background refresh without showing loading indicator
                viewModel.connectionManager.sendListSessions()
            }
        }
        .onChange(of: sessions.count) { _, _ in
            isLoading = false
        }
        .onChange(of: viewModel.connectionManager.state) { _, newState in
            if case .disconnected = newState, !disconnectRequested {
                // Detach from TerminalTabView sets detachRequested on the shared
                // viewModel — if set, navigate to sessions (handled by onDetach in
                // TerminalTabView), not to connect.
                if viewModel.detachRequested {
                    viewModel.detachRequested = false
                } else {
                    onDisconnect()
                }
            }
        }
        .sheet(isPresented: $showNewSessionSheet) {
            newSessionSheet
        }
        .alert("Switch Session", isPresented: $showConfirmSwitch, presenting: selectedSession) { session in
            Button("Cancel", role: .cancel) { selectedSession = nil }
            Button("Switch") {
                viewModel.connectionManager.sendSwitchSession(session.name)
                selectedSession = nil
                onOpen()
            }
        } message: { session in
            Text("Switch to tmux session \"\(session.name)\"?")
        }
        .alert("Delete Session", isPresented: $showConfirmDelete, presenting: sessionToDelete) { session in
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button("Delete", role: .destructive) {
                viewModel.killSession(name: session.name)
                sessionToDelete = nil
            }
        } message: { session in
            Text("Permanently delete tmux session \"\(session.name)\"? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sessions")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)

                if !sessions.isEmpty {
                    Text("\(sessions.count) tmux session\(sessions.count == 1 ? "" : "s")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)

            Text(connectionLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.5))

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(Color(white: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.06))
        .overlay(
            Rectangle()
                .fill(Color(white: 0.1))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var connectionColor: Color {
        switch viewModel.connectionManager.state {
        case .connected: return .green
        case .connecting, .reconnecting: return Color(white: 0.5)
        case .disconnected: return .red
        }
    }

    private var connectionLabel: String {
        switch viewModel.connectionManager.state {
        case .connected: return "CONNECTED"
        case .connecting: return "CONNECTING..."
        case .reconnecting(let n): return "RECONNECT #\(n)"
        case .disconnected: return "DISCONNECTED"
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(sessions) { tmuxSession in
                Button {
                    selectedSession = tmuxSession
                    showConfirmSwitch = true
                } label: {
                    TmuxSessionRow(session: tmuxSession)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(white: 0.06))
                .listRowSeparatorTint(Color(white: 0.1))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionToDelete = tmuxSession
                        showConfirmDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await refreshSessionList()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.split.2x2")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundColor(Color(white: 0.2))

            VStack(spacing: 6) {
                Text("No Tmux Sessions")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))
                Text("Create a new window or pull down\nto refresh the session list.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.3))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Button {
                requestSessionList()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                    Text("Refresh")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Color(white: 0.5))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Toolbar

    var bottomBar: some View {
        HStack(spacing: 0) {
            // New Session button
            Button {
                newSessionName = ""
                showNewSessionSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.square")
                        .font(.system(size: 14, weight: .medium))
                    Text("New Session")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(white: 0.08))
            }
            .buttonStyle(.plain)

            // Separator
            Rectangle()
                .fill(Color(white: 0.12))
                .frame(width: 0.5)

            // Disconnect button
            Button {
                disconnectRequested = true
                viewModel.disconnect()
                onDisconnect()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .medium))
                    Text("Disconnect")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Color(white: 0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(white: 0.06))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 48)
        .overlay(
            Rectangle()
                .fill(Color(white: 0.1))
                .frame(height: 0.5),
            alignment: .top
        )
        .background(Color(white: 0.04))
    }

    // MARK: - New Session Sheet

    private var newSessionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Enter a name for the new tmux session.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("Session name", text: $newSessionName)
                    .textContentType(.none)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color(white: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(white: 0.15), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)

                HStack(spacing: 12) {
                    Button {
                        showNewSessionSheet = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(white: 0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        let name = newSessionName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            viewModel.connectionManager.sendNewWindow(name)
                            // Bridge creates the session and switches to it —
                            // navigate directly to the terminal.
                        }
                        showNewSessionSheet = false
                        if !name.isEmpty {
                            onOpen()
                        }
                    } label: {
                        Text("Create")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(newSessionName.trimmingCharacters(in: .whitespaces).isEmpty ? Color(white: 0.3) : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(newSessionName.trimmingCharacters(in: .whitespaces).isEmpty ? Color(white: 0.04) : Color(white: 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(white: 0.12), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(newSessionName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .background(Color(white: 0.04).ignoresSafeArea())
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(240)])
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func requestSessionList() {
        guard case .connected = viewModel.connectionManager.state else { return }
        isLoading = true
        viewModel.connectionManager.sendListSessions()
    }

    private func refreshSessionList() async {
        guard case .connected = viewModel.connectionManager.state else { return }
        viewModel.connectionManager.sendListSessions()
        // Give the response a moment to arrive
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
    }
}

// MARK: - TmuxSessionRow

private struct TmuxSessionRow: View {

    let session: TmuxSessionInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text("\(session.windows) window\(session.windows == 1 ? "" : "s")")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.25))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#if DEBUG
struct SessionListView_Previews: PreviewProvider {
    static var previews: some View {
        SessionListView(onOpen: {}, onDisconnect: {})
            .environmentObject(TerminalViewModel())
            .preferredColorScheme(.dark)
    }
}
#endif
