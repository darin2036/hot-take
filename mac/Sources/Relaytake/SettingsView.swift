import AVFoundation
import AppKit
import CoreGraphics
import PlainspokenSpeech
import RelaytakeCore
import SwiftUI

enum Pref {
    static let quality = "videoQuality"
    static let microphone = "microphone"
    static let systemAudio = "systemAudio"
    /// Record with no sound at all: neither the microphone nor the computer's audio.
    static let noAudio = "noAudio"
    /// Unique ID of the chosen microphone; empty follows the system's default input.
    /// Leave Hot Take's own windows in a screen or area recording (to demo the app itself).
    static let includeOwnWindows = "includeOwnWindows"
    static let microphoneDevice = "recordingMicrophone"
    /// Unique ID of the camera to record alongside the screen; empty means no camera.
    static let cameraDevice = "recordingCamera"
    /// "small" or "large" (the default): how big the presenter circle is.
    static let presenterSize = "presenterSize"
    static let captions = "captions"
    /// Find chapters in a recording's transcript automatically and show them. On by default; each recording can override it.
    static let chapters = "chapters"
    static var chaptersByDefault: Bool { UserDefaults.standard.object(forKey: chapters) as? Bool ?? true }
    static let summary = "summary"
    /// Leave Notification Center out of screen and area recordings, so banners are not in the video.
    static let hideNotifications = "hideNotifications"
    /// Master switch for the global shortcuts.
    static let hotkeysEnabled = "hotkeysEnabled"
    /// The display recorded last, which Quick Record and screenshots use again.
    static let lastDisplay = "lastRecordedDisplay"
    static let speakerNotes = "speakerNotes"
    static let speakerNotesSize = "speakerNotesSize"
    static let playbackSpeed = "playbackSpeed"
    /// Play the rainbow welcome each time the app launches. On by default.
    static let showWelcome = "showWelcome"
    /// When a recording stops, turn it into a request for a coding agent and copy it. Off by default.
    static let recordForAgent = "recordForAgent"
}

/// Everything configurable lives here, not in the menu-bar dropdown. Panes follow the system's own
/// Settings windows: tabs along the top, grouped sections, explanations in tooltips. Each pane is
/// sized to its content so it only scrolls if it genuinely does not fit.
struct SettingsView: View {
    var body: some View {
        TabView {
            RecordingPane()
                .tabItem { Label("Recording", systemImage: "record.circle") }
            ProcessingPane()
                .tabItem { Label("Captions & Summary", systemImage: "captions.bubble") }
            PermissionsPane()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            LibraryPane()
                .tabItem { Label("Library", systemImage: "folder") }
        }
        // Side margins only: the tab bar already provides the top edge, and the grouped form has its
        // own inset, so extra top and bottom padding just reads as empty space.
        .scenePadding(.horizontal)
        .frame(width: 500)
    }
}

private extension View {
    /// Grouped pane that hugs its content and never bounces or scrolls when everything is visible.
    func settingsPane() -> some View {
        self.formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
            .fixedSize(horizontal: false, vertical: true)
            // The grouped form keeps a 20 pt inset above its first heading, which reads as empty space
            // under the tab bar. SwiftUI has no setting for it, so the form is nudged up; the lost
            // height comes off the window too, since each pane is sized to its content.
            .padding(.top, -12)
    }
}

private struct RecordingPane: View {
    @AppStorage(Pref.quality) private var quality = "medium"
    @AppStorage(Pref.microphone) private var microphone = true
    @AppStorage(Pref.systemAudio) private var systemAudio = true
    @AppStorage(Pref.microphoneDevice) private var microphoneID = ""
    @State private var microphones = Microphone.available()

    var body: some View {
        Form {
            Section {
                QualityPicker(value: $quality, audio: microphone || systemAudio, recording: true)
            } header: {
                Text("Video")
            }

            Section {
                Toggle("Record microphone", isOn: $microphone)
                    .help("Record your voice from the microphone.")
                if microphone {
                    Picker("Microphone", selection: Binding(
                        get: { microphones.contains { $0.id == microphoneID } ? microphoneID : "" },
                        set: { microphoneID = $0 })) {
                        ForEach(microphones) { Text($0.name).tag($0.id) }
                    }
                    .help("Which microphone to record. \"Default\" follows the Mac's current input.")
                    MicrophoneModeRow(owner: "settings", deviceID: microphoneID)
                }
                Toggle("Record system audio", isOn: $systemAudio)
                    .help("Record the sound your Mac plays. Your voice uses the microphone setting.")
            } header: {
                Text("Audio")
            }

            ShortcutsSection()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in microphones = Microphone.available() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in microphones = Microphone.available() }
        .settingsPane()
    }
}

private struct ProcessingPane: View {
    @AppStorage(Pref.captions) private var captions = true
    @AppStorage(Pref.summary) private var summary = true
    @AppStorage(Pref.chapters) private var chapters = true
    @AppStorage(SpeechPreferences.engineKey) private var engineChoice = AppleSpeechEngine.speechTranscriber.rawValue
    @AppStorage(SpeechPreferences.localeKey) private var localeChoice = ""
    @State private var locales: [Locale] = []
    @State private var vocabularyCount = SpeechPreferences.vocabulary.load().count

    private var engine: AppleSpeechEngine { AppleSpeechEngine(rawValue: engineChoice) ?? .speechTranscriber }

    var body: some View {
        Form {
            Section {
                Toggle("Make captions", isOn: $captions)
                    .help("Create a .vtt caption file on this Mac. Nothing is uploaded.")
                Toggle("Write a title and summary", isOn: $summary)
                    .help("Generate a title and summary on this Mac. Nothing is uploaded.")
                Toggle("Find chapters in transcripts", isOn: $chapters)
                    .help("Split a longer recording's transcript into titled parts, on this Mac. Nothing is uploaded. Each recording can turn chapters on or off from its transcript, and this is only the starting point.")
            } header: {
                Text("After recording")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if summary, let message = Summarizer.availabilityMessage { Text(message) }
                }
            }

            Section {
                Picker("Language", selection: $localeChoice) {
                    Text("Same as this Mac").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                    }
                    if !localeChoice.isEmpty, !locales.contains(where: { $0.identifier == localeChoice }) {
                        Text(localeChoice).tag(localeChoice)
                    }
                }
                .help("Pick the regional model that matches the speaker, such as English (India) or English (Australia). The first use of a language downloads the system's speech model through the system.")
                Picker("Recognizer", selection: $engineChoice) {
                    ForEach(AppleSpeechEngine.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .help("\(engine.benefit) \(engine.tradeoff)")
                LabeledContent("Vocabulary") {
                    HStack {
                        Text(vocabularyCount == 1 ? "1 entry" : "\(vocabularyCount) entries").foregroundStyle(.secondary)
                        Button("Open File") { NSWorkspace.shared.open(SpeechPreferences.vocabulary.ensureExists()) }
                        Button("Show in Folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([SpeechPreferences.vocabulary.ensureExists()])
                        }
                    }
                }
                .help("Names and product terms, one per line. For a word the recognizer keeps mishearing, add what it hears after an equals sign: Rovo=bravo|robo. Changes apply to the next captions you make.")
            } header: {
                Text("Speech recognition")
            }
        }
        .task(id: engineChoice) { locales = await SpeechAssets.supportedLocales(for: engine) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            vocabularyCount = SpeechPreferences.vocabulary.load().count  // edited in another app
        }
        .settingsPane()
    }
}

private struct PermissionsPane: View {
    @State private var screenAllowed = CGPreflightScreenCaptureAccess()
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        Form {
            Section {
                LabeledContent("Screen recording") {
                    HStack {
                        status(screenAllowed ? "Allowed" : "Not allowed", good: screenAllowed)
                        Button(screenAllowed ? "Open System Settings" : "Allow…") {
                            if !screenAllowed { screenAllowed = CGRequestScreenCaptureAccess() }
                            open("Privacy_ScreenCapture")
                        }
                    }
                }
                .help("the system may ask you to restart Hot Take after you allow screen recording.")
                LabeledContent("Microphone") {
                    HStack {
                        status(label(for: microphoneStatus), good: microphoneStatus == .authorized)
                        Button(microphoneStatus == .notDetermined ? "Allow…" : "Open System Settings") {
                            if microphoneStatus == .notDetermined {
                                AVCaptureDevice.requestAccess(for: .audio) { _ in refresh() }
                            } else {
                                open("Privacy_Microphone")
                            }
                        }
                    }
                }
            } header: {
                Text("Access")
            }
        }
        .settingsPane()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func status(_ text: String, good: Bool) -> some View {
        Label(text, systemImage: good ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(good ? Color.green : Color.secondary)
            .labelStyle(.titleAndIcon)
    }

    private func refresh() {
        screenAllowed = CGPreflightScreenCaptureAccess()
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func label(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Allowed"
        case .denied, .restricted: "Not allowed"
        default: "Not asked yet"
        }
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct LibraryPane: View {
    private let folder = TakeFiles.defaultDirectory()
    @AppStorage(Pref.showWelcome) private var showWelcome = true

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack {
                        Text(folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Show in Folder") {
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(folder)
                        }
                    }
                }
                .help("Recordings, captions and notes are ordinary files. Folders in Hot Take are also available in the file manager.")
            } header: {
                Text("Saved recordings")
            }
            Section {
                Toggle("Show the welcome animation", isOn: $showWelcome)
                    .help("The rainbow “What’s your Hot Take?” screen that plays each time Hot Take opens.")
            } header: {
                Text("At launch")
            }
        }
        .settingsPane()
    }
}
