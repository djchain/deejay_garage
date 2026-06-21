import SwiftUI

// MARK: - AppRoot
// Three-page navigation: Connect / Sessions / Terminal.
// Monochrome minimalist — pure black & white, no colors.

struct AppRoot: View {

    @StateObject private var viewModel = TerminalViewModel()
    @State private var navigation: Page = .connect

    enum Page {
        case connect
        case sessions
        case terminal
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            switch navigation {
            case .connect:
                ConnectView(onConnected: {
                    navigation = .sessions
                })
                .environmentObject(viewModel)

            case .sessions:
                SessionListView(
                    onOpen: {
                        navigation = .terminal
                    },
                    onDisconnect: {
                        navigation = .connect
                    }
                )
                .environmentObject(viewModel)

            case .terminal:
                TerminalTabView(
                    viewModel: viewModel,
                    onDetach: {
                        navigation = .sessions
                    },
                    onDisconnected: {
                        navigation = .connect
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}
