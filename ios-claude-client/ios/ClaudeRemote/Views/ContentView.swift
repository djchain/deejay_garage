import SwiftUI

// MARK: - ContentView
// Monochrome minimalist tab layout.

struct ContentView: View {

    @EnvironmentObject var viewModel: TerminalViewModel
    @State private var selectedTab: Tab = .terminal

    enum Tab: Hashable { case terminal, sessions, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            TerminalTabView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "terminal")
                    Text("Terminal")
                }
                .tag(Tab.terminal)

            SessionListView(
                onOpen: { selectedTab = .terminal },
                onDisconnect: { selectedTab = .sessions }
            )
                .tabItem {
                    Image(systemName: "clock")
                    Text("Sessions")
                }
                .tag(Tab.sessions)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(Tab.settings)
        }
        .tint(.white)
        .onAppear {
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
        .onChange(of: viewModel.bonjourDiscovery.discoveredServices) { _, services in
            // Auto-connect to first discovered Bonjour service if not connected
            if let first = services.first, case .disconnected = viewModel.connectionManager.state {
                viewModel.onServiceDiscovered(first)
            }
        }
    }
}
