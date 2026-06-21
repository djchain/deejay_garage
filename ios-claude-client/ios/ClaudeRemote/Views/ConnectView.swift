import SwiftUI

// MARK: - ConnectView
// Layer 1: Full-screen connection page.
// Monochrome minimalist — pure black & white, no colors.

struct ConnectView: View {

    let onConnected: () -> Void

    @EnvironmentObject var viewModel: TerminalViewModel

    // MARK: Local State

    @State private var manualHost: String = ""
    @State private var manualPort: String = "9090"
    @State private var hasConnected: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var sessionToDelete: SessionInfo?
    @State private var errorMessage: String?

    private var state: ConnectionState { viewModel.connectionManager.state }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerView
                    connectionStatusView
                    discoveredSection
                    manualSection
                    historySection
                }
            }
            .background(Color(white: 0.04).ignoresSafeArea())
            .onAppear {
                viewModel.startDiscovery()
                hasConnected = false
                errorMessage = nil
                // If already connected (e.g. auto-connect before view appeared), navigate forward
                if case .connected = state {
                    hasConnected = true
                    onConnected()
                }
            }
            .onDisappear {
                viewModel.stopDiscovery()
            }
            .onChange(of: state) { _, newState in
                onStateChange(newState)
            }
            .alert("Delete Session", isPresented: $showDeleteAlert, presenting: sessionToDelete) { session in
                Button("Cancel", role: .cancel) { sessionToDelete = nil }
                Button("Delete", role: .destructive) {
                    viewModel.sessionStore.remove(session.id)
                    sessionToDelete = nil
                }
            } message: { session in
                Text("\"\(session.name)\" will be removed from history.")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundColor(Color(white: 0.3))
                .padding(.top, 48)

            Text("Claude Remote")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color(white: 0.85))

            Text("Connect to your Mac bridge")
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.4))
                .padding(.bottom, 24)
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusView: some View {
        if case .disconnected = state, errorMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                Text(errorMessage!)
                    .font(.system(size: 12, design: .monospaced))
                Spacer()
                Button("Dismiss") {
                    withAnimation { errorMessage = nil }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.5))
            }
            .foregroundColor(Color(white: 0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(white: 0.12), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }

        if state != .disconnected || hasConnected {
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)

                Text(stateLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(stateColor)

                Spacer()

                if case .connected = state {
                    Text("Connected")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }

                if case .reconnecting = state {
                    Button("Cancel") {
                        viewModel.disconnect()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(white: 0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var stateColor: Color {
        switch state {
        case .connected: return .green
        case .connecting, .reconnecting: return Color(white: 0.5)
        case .disconnected: return errorMessage != nil ? .red : Color(white: 0.3)
        }
    }

    private var stateLabel: String {
        switch state {
        case .connected: return "CONNECTED"
        case .connecting: return "CONNECTING..."
        case .reconnecting(let n): return "RECONNECTING (#\(n))"
        case .disconnected:
            return errorMessage != nil ? "CONNECTION FAILED" : "DISCONNECTED"
        }
    }

    // MARK: - Discovered Services Section

    @ViewBuilder
    private var discoveredSection: some View {
        if !viewModel.bonjourDiscovery.discoveredServices.isEmpty {
            sectionView("Discovered Macs") {
                ForEach(viewModel.bonjourDiscovery.discoveredServices) { service in
                    Button {
                        viewModel.connectToDiscovered(service)
                        errorMessage = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 14))
                                .foregroundColor(Color(white: 0.5))
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(service.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("\(service.host):\(service.port)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color(white: 0.4))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(white: 0.25))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(white: 0.06))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Manual Connection Section

    private var manualSection: some View {
        sectionView("Manual Connection") {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TextField("192.168.1.100", text: $manualHost)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color(white: 0.05))

                    Rectangle()
                        .fill(Color(white: 0.12))
                        .frame(width: 0.5, height: 28)

                    TextField("9090", text: $manualPort)
                        .keyboardType(.numberPad)
                        .foregroundColor(.white)
                        .frame(width: 64)
                        .padding(12)
                        .background(Color(white: 0.05))
                }
                .background(Color(white: 0.06))

                Button {
                    errorMessage = nil
                    let port = Int(manualPort) ?? 9090
                    print("[ConnectView] Manual connect: \(manualHost):\(port)")
                    viewModel.connectManually(host: manualHost, port: port)
                } label: {
                    HStack {
                        Spacer()
                        Text("Connect")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(manualHost.isEmpty ? Color(white: 0.3) : .white)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(manualHost.isEmpty ? Color(white: 0.04) : Color(white: 0.08))
                }
                .buttonStyle(.plain)
                .disabled(manualHost.isEmpty)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.12), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Connection History Section

    @ViewBuilder
    private var historySection: some View {
        if !viewModel.sessionStore.sessions.isEmpty {
            sectionView("Recent") {
                ForEach(viewModel.sessionStore.sessions) { session in
                    Button {
                        errorMessage = nil
                        viewModel.connectToSession(session)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 14))
                                .foregroundColor(Color(white: 0.5))
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Text("\(session.host):\(session.port)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(Color(white: 0.4))
                            }
                            Spacer()
                            Text(session.lastUsed, style: .relative)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color(white: 0.3))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(white: 0.06))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.sessionStore.remove(
                            viewModel.sessionStore.sessions[index].id
                        )
                    }
                }
            }
        }
    }

    // MARK: - State Change Handler

    private func onStateChange(_ newState: ConnectionState) {
        switch newState {
        case .disconnected:
            if hasConnected {
                // Was connected before — treat as clean disconnect, no error
                return
            }
            // User hasn't initiated any connection yet — not an error
            if !manualHost.isEmpty || !viewModel.bonjourDiscovery.discoveredServices.isEmpty {
                errorMessage = "Connection failed. Check host and port."
            }
        case .connected:
            errorMessage = nil
            hasConnected = true
            onConnected()
        case .connecting, .reconnecting:
            errorMessage = nil
        }
    }

    // MARK: - Section Helper

    @ViewBuilder
    private func sectionView(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.35))
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) { content() }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.1), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
        }
    }
}
