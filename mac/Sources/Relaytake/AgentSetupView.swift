import AppKit
import RelaytakeCore
import SwiftUI

// Where a person finds out that an agent can record a demo for them, and how to connect one. A card at the top of the library
// (until it is dismissed or the feature is on), the menu-bar and Record menu items, and Settings all open the same sheet.

/// The slim card at the top of the library.
struct AgentCallout: View {
    @ObservedObject var recorder: RecorderModel
    @AppStorage(Pref.agentControl) private var enabled = false
    @AppStorage("agentCalloutDismissed") private var dismissed = false

    var body: some View {
        if !enabled, !dismissed {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Let an AI agent record your demo").font(.callout.weight(.semibold))
                    Text("Claude, Codex and other agents can use your app and have Hot Take record and tighten the video.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Set Up…") { recorder.showingAgentSetup = true }
                Button { dismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Hide this. You can still find it in the Record menu and the menu bar.")
                    .accessibilityLabel("Hide this suggestion")
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

struct AgentSetupSheet: View {
    @ObservedObject var recorder: RecorderModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Pref.agentControl) private var enabled = false
    @AppStorage(Pref.agentInput) private var inputEnabled = false
    @State private var client = AgentSetup.Client.claudeCode
    @State private var copied: String?
    @State private var connection = AgentConnector.State.notConnected
    @State private var connecting = false
    @State private var result: String?
    @State private var failed = false

    /// The `hottake` command inside this app.
    private var helper: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hottake").path }
    private var helperExists: Bool { FileManager.default.isExecutableFile(atPath: helper) }
    private var skill: String? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("skills/demo-recording/SKILL.md")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Let an AI agent record a demo").font(.title2.weight(.semibold))
                        Text("An agent on this Mac, such as Claude Code or Codex, can use an app while Hot Take records it, then cut the slow parts, add zooms and captions, and write a script for the voice-over. Everything stays on this Mac.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }

                    step(1, "Turn it on", trailing: status) {
                        Toggle("Let local agents control recording", isOn: $enabled)
                            .onChange(of: enabled) { _, _ in AgentServer.shared.refresh() }
                        Toggle("Also let agents use the mouse and keyboard", isOn: $inputEnabled)
                            .disabled(!enabled)
                            .help("Lets an agent move the pointer, click and type through the hottake command, so it can drive the app it is demoing. It acts as you, so only turn it on for an agent you trust. Off until you turn it on.")
                        Text("Optional. Without it an agent records and edits but cannot click or type for you.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    step(2, "Connect your agent, once") {
                        Picker("Agent", selection: $client) {
                            ForEach(AgentSetup.Client.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        let snippet = AgentSetup.snippet(for: client, helper: helper)
                        if AgentConnector.supportsConnect(client) {
                            connectRow
                            Text("Or add it yourself: " + snippet.instruction.prefix(1).lowercased() + snippet.instruction.dropFirst())
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(snippet.instruction).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        codeBox(snippet.text, label: "Copy")
                        if !helperExists {
                            Label("This copy of Hot Take does not have the hottake command inside it. Build the app with scripts/bundle.sh.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }

                    step(3, "Ask for a demo") {
                        Text("Paste this to your agent, and say what the demo should show. It plans first and waits for your OK before recording.")
                            .font(.callout).foregroundStyle(.secondary)
                        codeBox(AgentSetup.prompt(topic: "", helper: helper, skill: skill), label: "Copy Message")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("The recording bar stays on screen while an agent records, and its recording stops by itself after 30 minutes.", systemImage: "record.circle")
                        Label("Only programs run by your account can connect. Screen Recording permission is still yours to give.", systemImage: "lock.shield")
                        Label("Agents record screens only here, not windows or the camera. Watch the finished video before sharing it.", systemImage: "eye")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: Self.contentWidth, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack {
                Button("Open Help") { openHelp() }.buttonStyle(.link)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: Self.contentWidth + 40, height: 640)
        .onAppear { refreshConnection() }
        .onChange(of: client) { _, _ in result = nil; failed = false; refreshConnection() }
    }

    private func refreshConnection() { connection = AgentConnector.state(of: client, helper: helper) }

    /// The Connect button for the chosen agent, with what it did or why it could not.
    @ViewBuilder private var connectRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(connection == .notConnected ? "Connect \(client.rawValue)" : "Reconnect") { run { try await AgentConnector.connect(client, helper: helper) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(connecting || !helperExists)
                    .help("Adds Hot Take to \(AgentConnector.displayPath(client)). Your other settings there are kept, and a backup copy is saved first.")
                if connection != .notConnected {
                    Button("Disconnect") { run { try await AgentConnector.disconnect(client) } }
                        .disabled(connecting)
                        .help("Removes Hot Take from \(AgentConnector.displayPath(client)).")
                }
                if connecting { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            if let result {
                Label(result, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(failed ? Color.orange : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connection == .connected {
                Label("Connected. \(AgentConnector.restartHint(client))", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else if connection == .otherCopy {
                Label("Connected to a different copy of Hot Take. Click Reconnect to use this one.", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func run(_ action: @escaping () async throws -> String) {
        connecting = true
        result = nil
        Task {
            do { result = try await action(); failed = false } catch { result = error.localizedDescription; failed = true }
            connecting = false
            refreshConnection()
        }
    }

    private static let contentWidth: CGFloat = 580

    @ViewBuilder private var status: some View {
        if !enabled {
            Text("Off. Agents cannot connect.").font(.callout).foregroundStyle(.secondary)
        } else if let seen = recorder.agentLastSeen {
            Label {
                Text("An agent connected ") + Text(seen, style: .relative) + Text(" ago.")
            } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            .font(.callout)
        } else {
            Text("On. Waiting for an agent to connect.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        step(number, title, trailing: EmptyView(), content)
    }

    private func step<Content: View, Trailing: View>(
        _ number: Int, _ title: String, trailing: Trailing, @ViewBuilder _ content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(.tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    trailing
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeBox(_ text: String, label: String) -> some View {
        let done = copied == text
        return Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10).padding(.vertical, 10).padding(.trailing, 34)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = text
                } label: {
                    Image(systemName: done ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(done ? Color.green : Color.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(4)
                .help(done ? "Copied" : label)
                .accessibilityLabel(label)
            }
    }

    private func openHelp() {
        dismiss()
        HelpContent.pendingTopic = "Let an agent record a demo"
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "help")
        NotificationCenter.default.post(name: .showHelpTopic, object: nil)
    }
}
