import SwiftUI
import SwiftTerm
import class UIKit.UIColor

// MARK: - TerminalViewProxy
/// Holds a weak reference to the active TerminalView so output can be fed
/// directly without going through SwiftUI's @Binding + onChange cycle.
final class TerminalViewProxy: ObservableObject {
    weak var terminalView: TerminalView?
}

// MARK: - TerminalTabView
// Three-layer layout: top bar (40px), terminal area, bottom bar (56px)
// Monochrome minimalist: black terminal, white text, hairline dividers.

struct TerminalTabView: View {

    @ObservedObject var viewModel: TerminalViewModel
    var onDetach: () -> Void = {}
    var onDisconnected: () -> Void = {}

    @StateObject private var proxy = TerminalViewProxy()
    @State private var isDetaching: Bool = false
    /// Tracks the current connection generation to detect new connections.
    @State private var observedGeneration: Int = 0

    // MARK: Body

    var body: some View {
        ZStack {
            Color(white: 0.02).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar (40px)
                topBar

                // Hairline divider
                Rectangle()
                    .fill(Color(white: 0.12))
                    .frame(height: 0.5)

                // Terminal area
                SwiftTermView(
                    proxy: proxy,
                    fontSize: viewModel.fontSize,
                    onByteInput: { bytes in
                        if let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty {
                            viewModel.sendInput(text)
                        }
                    },
                    onResize: { cols, rows in
                        viewModel.sendResize(cols: cols, rows: rows)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Hairline divider above bottom bar
                Rectangle()
                    .fill(Color(white: 0.12))
                    .frame(height: 0.5)

                // Bottom bar (56px)
                bottomBar
            }
        }
        .onChange(of: viewModel.connectionManager.state) { _, newState in
            if case .disconnected = newState {
                // Clear the terminal screen on disconnect
                proxy.terminalView?.feed(text: "\u{1b}[2J\u{1b}[H")
                if !isDetaching {
                    onDisconnected()
                }
                isDetaching = false
            }
        }
        .onAppear {
            // Feed output directly to TerminalView, bypassing SwiftUI cycle
            viewModel.connectionManager.onOutput = { [weak proxy] text in
                guard !text.isEmpty, let tv = proxy?.terminalView else { return }
                DispatchQueue.main.async {
                    tv.feed(text: text)
                }
            }
            // Listen for tmux detach events (prefix+d) from the bridge.
            // When the bridge detects PTY exit and sends session_detached,
            // navigate to the session list without disconnecting WebSocket.
            viewModel.connectionManager.onSessionDetached = { [weak viewModel] sessionName in
                guard let vm = viewModel else { return }
                vm.detachRequested = true
                DispatchQueue.main.async {
                    onDetach()
                }
            }
        }
    }

    // MARK: Top Bar (40px)

    private var topBar: some View {
        HStack(spacing: 0) {
            // Session name + dropdown arrow
            HStack(spacing: 6) {
                Text(sessionDisplayName)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.leading, 16)

            Spacer()

            // Detach button — send Ctrl+B d to detach tmux, then return to
            // Layer 2 (sessions). WebSocket stays alive so the session list
            // can be fetched without reconnecting.
            Button(action: {
                isDetaching = true
                viewModel.detachRequested = true
                // Send prefix+d to detach the tmux client. The bridge will
                // detect PTY exit and send session_detached back, which
                // triggers onDetach() via onSessionDetached callback.
                // If the bridge is an older version, onDetach() is called
                // here as a fallback — SessionListView will refresh when
                // the WebSocket state settles.
                viewModel.sendInput("\u{02}d")
                onDetach()
            }) {
                Text("Detach")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
        }
        .frame(height: 40)
        .background(Color(white: 0.04))
    }

    /// Display name for the current session — falls back to first saved session or "Terminal".
    private var sessionDisplayName: String {
        viewModel.sessionStore.sessions.first?.name ?? "Terminal"
    }

    // MARK: Bottom Bar (56px)

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 20)
            bottomButton("Ctrl-C") { viewModel.sendSignal("int") }
            Spacer(minLength: 20)
            bottomButton("Esc") { viewModel.sendInput("\u{1b}") }
            Spacer(minLength: 20)
            bottomButton("Tab") { viewModel.sendInput("\t") }
            Spacer(minLength: 20)
            bottomButton("\u{25B2}") { viewModel.sendInput("\u{1b}[A") }
            Spacer(minLength: 20)
            bottomButton("\u{25BC}") { viewModel.sendInput("\u{1b}[B") }
            Spacer(minLength: 20)
        }
        .frame(height: 56)
        .background(Color(white: 0.04))
    }

    /// A bottom bar button — plain text label, no border, min 44 pt touch target.
    private func bottomButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            if viewModel.hapticFeedbackEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            action()
        }) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.55))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SwiftTerm UIViewRepresentable

struct SwiftTermView: UIViewRepresentable {

    @ObservedObject var proxy: TerminalViewProxy
    var fontSize: Double
    var onByteInput: (([UInt8]) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView()
        terminal.terminalDelegate = context.coordinator
        terminal.getTerminal().setCursorStyle(.steadyBlock)
        let font = UIFont(name: "Menlo-Regular", size: fontSize)
            ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.font = font
        terminal.nativeBackgroundColor = UIColor(white: 0.02, alpha: 1)
        terminal.nativeForegroundColor = UIColor.white
        // Store reference so output can be fed directly
        DispatchQueue.main.async { [weak proxy] in
            proxy?.terminalView = terminal
        }
        return terminal
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // Update proxy reference (in case UIView was recreated)
        if proxy.terminalView !== uiView {
            proxy.terminalView = uiView
        }
        if uiView.font.pointSize != fontSize {
            let font = UIFont(name: "Menlo-Regular", size: fontSize)
                ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            uiView.font = font
        }
        // Always monochrome
        uiView.nativeBackgroundColor = UIColor(white: 0.02, alpha: 1)
        uiView.nativeForegroundColor = UIColor.white
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        var parent: SwiftTermView
        init(parent: SwiftTermView) { self.parent = parent }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            parent.onResize?(newCols, newRows)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            parent.onByteInput?(bytes)
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func selectionChanged(source: TerminalView) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { UIApplication.shared.open(url) }
        }

        func rangeOfTerminal(in source: TerminalView) -> NSRange? { nil }
    }
}
