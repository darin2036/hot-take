import RelaytakeCore
import SwiftUI

/// Settings ▸ Voice: which voice speaks a voiceover. The default is a voice that runs on this Mac and sends nothing anywhere. A voice from
/// the person's own ElevenLabs account is the other choice; it sends the words of a voiceover to ElevenLabs, and only once they sign in.
struct VoicePane: View {
    @ObservedObject private var account = ElevenLabsAccount.shared
    @ObservedObject private var local = LocalVoiceStore.shared
    @AppStorage(Pref.voiceSource) private var sourceChoice = VoiceProvider.Source.local.rawValue
    @AppStorage(Pref.elevenLabsModel) private var modelID = ElevenLabs.Model.multilingualV2.id
    @AppStorage(Pref.elevenLabsAgents) private var agentsAllowed = false
    @State private var pasted = ""
    @State private var confirmRemove = false

    private var source: VoiceProvider.Source { VoiceProvider.Source(rawValue: sourceChoice) ?? .local }

    var body: some View {
        Form {
            Section {
                Picker("Speak with", selection: $sourceChoice) {
                    ForEach(VoiceProvider.Source.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .help("Who speaks the voiceover in the Studio and in an agent's demo.")
            } footer: {
                Text(source == .local
                    ? "A voice that runs on this Mac. Nothing you write or record is sent anywhere."
                    : "A voice from your ElevenLabs account. The words of a voiceover are sent to ElevenLabs.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch source {
            case .local: localSections
            case .elevenLabs:
                if account.signedIn { signedInSections } else { signedOutSection }
            }
        }
        .task {
            local.refresh()
            if account.signedIn { await account.refresh() }
        }
        .settingsPane()
    }

    // MARK: On this Mac

    @ViewBuilder private var localSections: some View {
        switch local.state {
        case .ready:
            Section {
                Picker("Voice", selection: Binding(get: { local.voice.id }, set: { id in
                    if let voice = KokoroModel.voice(id: id) { local.choose(voice) }
                })) {
                    ForEach(KokoroModel.voices) { Text($0.title).tag($0.id) }
                }
                .help("English voices. The first line of a voiceover takes a few seconds longer while the model loads.")
                LabeledContent("Downloaded") {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(KokoroModel.totalBytes), countStyle: .file)).foregroundStyle(.secondary)
                        Button("Remove…") { confirmRemove = true }
                            .help("Deletes the downloaded voice from this Mac. You can download it again.")
                    }
                }
            } header: {
                Text("Voice on this Mac")
            } footer: {
                Text("Kokoro, an open model (Apache-2.0), running on your Mac's GPU. English only.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .confirmationDialog("Remove the downloaded voice?", isPresented: $confirmRemove) {
                Button("Remove", role: .destructive) { local.remove() }
            } message: {
                Text("It is removed from this Mac only. Voiceovers you already made stay in your takes, and you can download the voice again.")
            }
        case .downloading(let bytes, let total):
            Section {
                ProgressView(value: Double(bytes), total: Double(max(1, total)))
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { local.cancelDownload() }
                }
            } header: {
                Text("Downloading the voice")
            }
        case .notInstalled, .failed:
            Section {
                if case .failed(let message) = local.state {
                    Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Download Voice (\(ByteCountFormatter.string(fromByteCount: Int64(KokoroModel.totalBytes), countStyle: .file)))") {
                        local.download()
                    }
                }
            } header: {
                Text("Voice on this Mac")
            } footer: {
                Text("A one-time download of Kokoro, an open speech model (Apache-2.0), and ten English voices, from \(KokoroModel.host). Each file is checked against a fixed fingerprint before it is used. Only that download uses the network; speaking a line never does.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        agentsSection(
            "When an agent's edit asks for a voiceover, Hot Take speaks its narration lines with this voice. It runs on this Mac and costs nothing. Also needs Let local agents control recording in the Recording tab.")
    }

    private func agentsSection(_ text: String) -> some View {
        Section {
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Agents")
        }
    }

    // MARK: ElevenLabs, signed out

    private var signedOutSection: some View {
        Section {
            SecureField("API key", text: $pasted)
                .textContentType(.password)
                .onSubmit(signIn)
                .help("Paste a key from your ElevenLabs account. It is checked with ElevenLabs, then kept in your Mac's Keychain.")
            HStack {
                Button("Get a Key…") { NSWorkspace.shared.open(ElevenLabs.keysPage) }
                    .help("Opens ElevenLabs in your browser. Sign in there, make an API key and copy it.")
                Spacer()
                if account.busy { ProgressView().controlSize(.small) }
                Button("Sign In", action: signIn)
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account.busy)
                    .keyboardShortcut(.defaultAction)
            }
            if let problem = account.problem {
                Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("ElevenLabs voice")
        } footer: {
            Text("Speak a voiceover in an AI voice from your own ElevenLabs account. ElevenLabs does not offer a browser sign-in to other apps, so Hot Take uses an API key. In ElevenLabs you can limit the key to Text to Speech, Voices (read) and User (read). The key stays in your Keychain. Only the lines to be spoken are sent, only to \(ElevenLabs.host), and only when you ask for a voiceover. Your ElevenLabs plan is charged for them.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func signIn() {
        let key = pasted
        Task {
            await account.signIn(pasted: key)
            if account.signedIn { pasted = "" }
        }
    }

    // MARK: ElevenLabs, signed in

    @ViewBuilder private var signedInSections: some View {
        Section {
            LabeledContent("Account") {
                HStack {
                    Text(planText).foregroundStyle(.secondary)
                    Button("Sign Out") { account.signOut() }
                        .help("Removes the key from your Keychain. Voiceovers already made stay in your takes.")
                }
            }
            if let problem = account.problem {
                Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("ElevenLabs voice")
        }

        Section {
            Picker("Voice", selection: Binding(
                get: { account.voices.contains { $0.id == account.voiceID } ? account.voiceID : "" },
                set: { id in if let voice = account.voices.first(where: { $0.id == id }) { account.choose(voice) } })) {
                if !account.voices.contains(where: { $0.id == account.voiceID }) {
                    Text(account.voices.isEmpty ? "Loading voices…" : "Choose a voice").tag("")
                }
                ForEach(account.voices) { Text($0.name).tag($0.id) }
            }
            .help("A voice on your ElevenLabs account, including any you made or added there.")
            Picker("Model", selection: $modelID) {
                ForEach(ElevenLabs.Model.all) { Text($0.title).tag($0.id) }
            }
            .help(ElevenLabs.Model.named(modelID).detail)
        } header: {
            Text("Speak with")
        } footer: {
            Text(ElevenLabs.Model.named(modelID).detail).fixedSize(horizontal: false, vertical: true)
        }

        Section {
            Toggle("Let local agents make a demo's voiceover", isOn: $agentsAllowed)
                .help("When an agent's edit asks for a voiceover with this voice, Hot Take speaks its narration lines with your account. This spends your ElevenLabs characters, so it is off until you turn it on. An agent never sees your key, and no more than \(ElevenLabs.agentCharacterLimit) characters are spoken in one edit.")
        } header: {
            Text("Agents")
        } footer: {
            Text("Also needs Let local agents control recording in the Recording tab. Up to \(ElevenLabs.agentCharacterLimit) characters are spoken per edit.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var planText: String {
        guard let plan = account.subscription else { return "Signed in" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let left = formatter.string(from: NSNumber(value: plan.remaining)) ?? "\(plan.remaining)"
        return "\(left) characters left"
    }
}
