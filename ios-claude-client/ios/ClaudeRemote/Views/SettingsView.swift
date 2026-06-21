import SwiftUI

// MARK: - SettingsView
// Monochrome minimalist: hairline sections, monospaced labels, flat controls.

struct SettingsView: View {

    @EnvironmentObject var viewModel: TerminalViewModel

    @State private var manualHost: String = ""
    @State private var manualPort: String = "9090"
    @FocusState private var isHostFocused: Bool
    @FocusState private var isPortFocused: Bool

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Display
                    settingsSection("Display") {
                        // Font size
                        VStack(spacing: 8) {
                            HStack {
                                Text("Font Size")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("\(Int(viewModel.fontSize))pt")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Color(white: 0.4))
                            }
                            Slider(value: $viewModel.fontSize, in: 12...24, step: 1) {
                                Text("Font Size")
                            } minimumValueLabel: {
                                Text("12").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.3))
                            } maximumValueLabel: {
                                Text("24").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.3))
                            }
                            .tint(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        settingsDivider()

                        // Theme
                        HStack {
                            Text("Theme")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Picker("", selection: $viewModel.terminalTheme) {
                                ForEach(TerminalTheme.allCases, id: \.self) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(.white)
                            .frame(width: 180)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    // Manual server
                    settingsSection("Manual Server") {
                        HStack(spacing: 0) {
                            TextField("192.168.1.100", text: $manualHost)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .foregroundColor(.white)
                                .padding(12)
                                .focused($isHostFocused)
                            Rectangle().fill(Color(white: 0.12)).frame(width: 0.5, height: 28)
                            TextField("9090", text: $manualPort)
                                .keyboardType(.numberPad)
                                .foregroundColor(.white)
                                .frame(width: 64)
                                .padding(12)
                                .focused($isPortFocused)
                        }
                        .background(Color(white: 0.06))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.1), lineWidth: 0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Button(action: connectToManualServer) {
                            HStack {
                                Spacer()
                                Text("Connect")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(manualHost.trimmingCharacters(in: .whitespaces).isEmpty ? Color(white: 0.25) : .white)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(Color(white: 0.08))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.12), lineWidth: 0.5))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.bottom, 12)
                    }

                    // Behavior
                    settingsSection("Behavior") {
                        settingsToggle("Haptic Feedback", icon: "hand.tap", isOn: $viewModel.hapticFeedbackEnabled)
                        settingsDivider()
                        settingsToggle("Auto-Reconnect", icon: "arrow.triangle.2.circlepath", isOn: .constant(true))
                    }

                    // About
                    settingsSection("About") {
                        settingsInfoRow("Version", "1.0.0")
                        settingsDivider()
                        settingsInfoRow("Build", "1")
                        settingsDivider()
                        Button {
                            if let url = URL(string: "https://github.com/migueldeicaza/SwiftTerm") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Text("SwiftTerm")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("github.com")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(white: 0.35))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        settingsDivider()

                        Button {
                            if let url = URL(string: "https://claude.ai") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Text("Claude")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Text("claude.ai")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(white: 0.35))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsFooter("Claude Remote · iOS · Terminal Bridge")
                }
            }
            .background(Color(white: 0.04))
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.immediately)
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside text fields
            isHostFocused = false
            isPortFocused = false
        }
    }

    // MARK: Section Builder

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.3))
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 8)
            VStack(spacing: 0) { content() }
                .background(Color(white: 0.06))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.1), lineWidth: 0.5))
                .padding(.horizontal, 16)
        }
    }

    private func settingsDivider() -> some View {
        Rectangle()
            .fill(Color(white: 0.1))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private func settingsFooter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(Color(white: 0.25))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 32)
            .padding(.bottom, 40)
    }

    private func settingsToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .tint(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func settingsInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(white: 0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Actions

    private func connectToManualServer() {
        isHostFocused = false
        isPortFocused = false
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        let port = Int(manualPort) ?? 9090
        guard !host.isEmpty else { return }
        viewModel.connectManually(host: host, port: port)
        manualHost = ""
        manualPort = "9090"
    }
}
