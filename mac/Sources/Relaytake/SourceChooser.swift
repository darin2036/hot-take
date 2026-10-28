import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// One open window offered in the record sheet.
private struct WindowChoice: Identifiable {
    let id: CGWindowID
    let window: SCWindow
    var app: String { window.owningApplication?.applicationName ?? "Window" }
    var title: String { window.title ?? "" }
    var icon: NSImage? {
        guard let pid = window.owningApplication?.processID else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.icon
    }
}

struct SourceChooser: View {
    @AppStorage(Pref.quality) private var quality = "medium"
    @AppStorage(Pref.systemAudio) private var systemAudio = true
    @AppStorage(Pref.noAudio) private var noAudio = false
    @AppStorage(Pref.microphone) private var microphoneOn = true
    @AppStorage(Pref.presenterSize) private var presenterSize = PresenterSize.large.rawValue
    /// The camera last used, so switching the presenter back on picks it again.
    @AppStorage("recordingCameraLast") private var lastCameraID = ""
    @AppStorage(Pref.includeOwnWindows) private var includeOwnWindows = false
    @AppStorage(Pref.microphoneDevice) private var microphoneID = ""
    @AppStorage(Pref.cameraDevice) private var cameraID = ""
    @State private var cameras = CameraChoice.available()
    @State private var effects = CameraEffectsStatus.current()
    @ObservedObject var recorder: RecorderModel
    @State private var mode: String

    init(recorder: RecorderModel, mode: String = "screen") {
        self.recorder = recorder
        _mode = State(initialValue: mode)
    }
    @State private var screens = NSScreen.screens
    @State private var selected: CGDirectDisplayID?
    @State private var previews: [CGDirectDisplayID: NSImage] = [:]
    @State private var windows: [WindowChoice] = []
    @State private var windowPreviews: [CGWindowID: NSImage] = [:]
    @State private var selectedWindow: CGWindowID?
    @State private var microphones = Microphone.available()
    @State private var refresh = UUID()
    @State private var previewMessage = ""
    @State private var windowGridHeight: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record").font(.title2.bold())
            HStack {
                Picker("Record", selection: $mode) {
                    Text("Screen").tag("screen")
                    Text("Window or app").tag("window")
                    Text("Area").tag("area")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 340)
                Spacer()
                if mode == "screen", screens.count > 1 {
                    Button("Show screen numbers", systemImage: "number.square") { ScreenIdentifiers.shared.show(screens) }
                        .controlSize(.small)
                        .help("Briefly puts each screen's number on that screen.")
                }
            }

            switch mode {
            case "screen": screenSection
            case "window": windowSection
            default:
                Text("Drag over any part of your screen after you press Select area. The area stays fixed, even if a window moves.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            }

            controls

            HStack {
                if mode != "window" { moreMenu }
                if !previewMessage.isEmpty { Text(previewMessage).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("Cancel") { recorder.choosing = false }.keyboardShortcut(.cancelAction)
                Button(mode == "screen" ? "Start recording" : mode == "window" ? "Start recording" : "Select area…") {
                    ScreenIdentifiers.shared.hide()
                    if mode == "screen", let selected { recorder.begin(.screen(selected)) }
                    else if mode == "window", let window = windows.first(where: { $0.id == selectedWindow }) {
                        recorder.begin(.window(SCContentFilter(desktopIndependentWindow: window.window)))
                    }
                    else if mode == "area" { recorder.begin(.area) }
                }
                .help(mode == "window" ? "Record the window you selected after a 3–2–1 countdown." : mode == "area" ? "Drag over the area you want to record." : "Record the selected screen after a 3–2–1 countdown.")
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled((mode == "screen" && !screens.contains { $0.displayID == selected })
                    || (mode == "window" && !windows.contains { $0.id == selectedWindow }))
            }
        }
        .padding(20).frame(width: 600)
        .task(id: "\(refresh)-\(mode)") { await loadSources() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            if !screens.contains(where: { $0.displayID == selected }) { selected = nil }
            ScreenIdentifiers.shared.hide()
            refresh = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in microphones = Microphone.available() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in microphones = Microphone.available() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in cameras = CameraChoice.available() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in cameras = CameraChoice.available() }
        .task(id: cameraID) { await updateCamera() }
        .task {
            // The system's effects can be switched on its own panel while this sheet is open.
            while !Task.isCancelled {
                if !chosenCamera.isEmpty { effects = CameraEffectsStatus.current() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            // "No audio" used to be a separate box; it is now just both sound switches off.
            if noAudio { microphoneOn = false; systemAudio = false; noAudio = false }
        }
        .onDisappear {
            ScreenIdentifiers.shared.hide()
            // Closing the sheet to start a recording must not switch the camera off just before it is needed.
            if recorder.phase == .idle { recorder.camera.stopPreview() }
        }
    }

    // MARK: Camera

    private var chosenCamera: String { cameras.contains { $0.id == cameraID } ? cameraID : "" }

    private func updateCamera() async {
        guard !chosenCamera.isEmpty else { recorder.camera.stopPreview(); return }
        await recorder.camera.requestAccess()
        if await recorder.camera.configure(cameraID: chosenCamera) { recorder.camera.startPreview() }
    }

    /// What goes into the recording besides the picture: one switch per source, in a single panel. A switch that is
    /// on shows its device menu beside it; the presenter also shows a live preview underneath.
    private var controls: some View {
        VStack(spacing: 0) {
            sourceRow("Microphone", symbol: microphoneOn ? "mic.fill" : "mic.slash", isOn: $microphoneOn) {
                devicePicker("Microphone", selection: Binding(
                    get: { microphones.contains { $0.id == microphoneID } ? microphoneID : "" },
                    set: { microphoneID = $0 }), choices: microphones.map { ($0.id, $0.name) })
                    .help("Which microphone to record. \"Default\" follows the Mac's current input.")
            }
            Divider().padding(.leading, 30)
            sourceRow("Computer audio", symbol: systemAudio ? "speaker.wave.2.fill" : "speaker.slash", isOn: $systemAudio) { EmptyView() }
                .help("Also record the sound your Mac plays.")
            Divider().padding(.leading, 30)
            sourceRow("Presenter", symbol: presenterOn.wrappedValue ? "person.crop.circle.fill" : "person.crop.circle", isOn: presenterOn) {
                devicePicker("Camera", selection: Binding(get: { chosenCamera }, set: { cameraID = $0 }),
                             choices: cameras.map { ($0.id, $0.name) })
            }
            .help("Put yourself in the video as a circle you can move while recording, and later in the Studio.")
            .disabled(cameras.isEmpty)
            if presenterOn.wrappedValue { presenterDetail.padding(.leading, 40).padding(.bottom, 10) }
            Divider().padding(.leading, 30)
            HStack(spacing: 10) {
                Image(systemName: "film").frame(width: 20).foregroundStyle(.secondary)
                Text("File size")
                Spacer()
                QualityPicker(value: $quality, audio: microphoneOn || systemAudio, recording: true, menu: true)
                    .labelsHidden().fixedSize()
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private func sourceRow<Device: View>(_ title: String, symbol: String, isOn: Binding<Bool>, @ViewBuilder device: () -> Device) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20)
                .foregroundStyle(isOn.wrappedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(title)
            Spacer(minLength: 8)
            if isOn.wrappedValue { device() }
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .frame(minHeight: 36)
        .animation(.easeOut(duration: 0.15), value: isOn.wrappedValue)
    }

    private func devicePicker(_ title: String, selection: Binding<String>, choices: [(String, String)]) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices, id: \.0) { Text($0.1).tag($0.0) }
        }
        .labelsHidden().pickerStyle(.menu).frame(width: 220)
    }

    /// The presenter is on when a camera is chosen. Switching it on picks the camera used last time.
    private var presenterOn: Binding<Bool> {
        Binding(get: { !chosenCamera.isEmpty }, set: { on in
            if on {
                cameraID = cameras.contains { $0.id == lastCameraID } ? lastCameraID : (cameras.first?.id ?? "")
            } else {
                if !chosenCamera.isEmpty { lastCameraID = chosenCamera }
                cameraID = ""
            }
        })
    }

    @ViewBuilder private var presenterDetail: some View {
        if recorder.camera.isAuthorized {
            HStack(alignment: .top, spacing: 12) {
                CameraPreview(session: recorder.camera.session)
                    .frame(width: 144, height: 81)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Camera preview")
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Presenter size", selection: $presenterSize) {
                        ForEach(PresenterSize.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .help("How big your circle is in the video.")
                    Button("Video Effects…") { AVCaptureDevice.showSystemUserInterface(.videoEffects) }
                        .controlSize(.small)
                        .help("Opens the system's panel for background blur, Center Stage, Studio Light and more.")
                }
                Spacer(minLength: 0)
            }
        } else {
            Text(recorder.camera.status == .notDetermined
                 ? "Hot Take will ask to use the camera."
                 : "Camera access is off. Turn it on in System Settings → Privacy & Security → Camera.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Options most recordings never need.
    private var moreMenu: some View {
        Menu {
            Toggle("Show Hot Take in the recording", isOn: $includeOwnWindows)
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More options. Show Hot Take in the recording leaves this app's windows in the video, for demoing the app itself.")
    }

    // MARK: Screens

    @ViewBuilder private var screenSection: some View {
        let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12, alignment: .top)]
        let grid = LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(Array(screens.enumerated()), id: \.element.displayID) { index, screen in
                if let id = screen.displayID { screenCard(screen, id: id, number: index + 1) }
            }
        }.padding(3)
        if screens.count > 4 { ScrollView { grid }.frame(height: 300) } else { grid }
    }

    private func screenCard(_ screen: NSScreen, id: CGDirectDisplayID, number: Int) -> some View {
        let isSelected = selected == id
        return Button { selected = id } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    if let preview = previews[id] {
                        Image(nsImage: preview).resizable().scaledToFill()
                    } else {
                        Image(systemName: "display").font(.system(size: 30)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if screens.count > 1 {
                        Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Color.accentColor, in: Circle()).padding(5)
                    }
                }
                .aspectRatio(max(0.5, screen.frame.width / max(1, screen.frame.height)), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                HStack {
                    Text(screen.localizedName).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                }.font(.callout)
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Screen \(number), \(screen.localizedName)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Windows

    @ViewBuilder private var windowSection: some View {
        if windows.isEmpty {
            Text(previewMessage.isEmpty ? "Looking for open windows…" : "No windows to show yet.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 90)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                    ForEach(windows) { windowCard($0) }
                }
                .padding(3)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { windowGridHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Only as tall as the windows need, up to a cap. (fixedSize on the ScrollView let the grid spill
            // past the cap and over the controls above and below it.)
            .frame(height: min(270, max(90, windowGridHeight)))
            .clipped()
        }
        HStack(spacing: 10) {
            Text("A browser is recorded as the window shows it, so switch to the tab you want first. the system doesn't let apps record one background tab.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Use system picker…") { ScreenIdentifiers.shared.hide(); recorder.begin(.windowOrApp) }
                .controlSize(.small)
                .help("Choose a whole app (all its windows) in the system picker.")
        }
    }

    private func windowCard(_ choice: WindowChoice) -> some View {
        let isSelected = selectedWindow == choice.id
        return Button { selectedWindow = choice.id } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                    if let image = windowPreviews[choice.id] {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }.frame(height: 88).clipShape(RoundedRectangle(cornerRadius: 5))
                HStack(spacing: 5) {
                    if let icon = choice.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(choice.app).font(.callout.weight(.medium)).lineLimit(1)
                        if !choice.title.isEmpty { Text(choice.title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help([choice.app, choice.title].filter { !$0.isEmpty }.joined(separator: " — "))
            .accessibilityLabel("\(choice.app) \(choice.title)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Loading

    @MainActor private func loadSources() async {
        if selected == nil { selected = NSScreen.main?.displayID ?? screens.first?.displayID }
        guard CGPreflightScreenCaptureAccess() else {
            previewMessage = "Previews appear after Screen Recording access is allowed."
            return
        }
        previewMessage = ""
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ours = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            if mode == "window" {
                await loadWindows(content)
            } else if mode == "screen" {
                previews = [:]
                for display in content.displays {
                    try Task.checkCancellation()
                    let config = SCStreamConfiguration()
                    config.width = 480
                    config.height = max(2, Int(480 * Double(display.height) / Double(max(1, display.width))))
                    config.showsCursor = false
                    let filter = SCContentFilter(display: display, excludingApplications: ours, exceptingWindows: [])
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    try Task.checkCancellation()
                    previews[display.displayID] = NSImage(cgImage: image, size: .zero)
                }
            }
        } catch is CancellationError { return }
        catch { previewMessage = "Preview unavailable." }
    }

    @MainActor private func loadWindows(_ content: SCShareableContent) async {
        let candidates = content.windows
            .filter { $0.windowLayer == 0 && $0.isOnScreen && $0.frame.width >= 120 && $0.frame.height >= 80 }
            .filter { $0.owningApplication != nil }
            .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            .prefix(18)
        windows = candidates.map { WindowChoice(id: $0.windowID, window: $0) }
        if !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = nil }
        for choice in windows {
            if Task.isCancelled { return }
            let config = SCStreamConfiguration()
            config.width = 360
            config.height = max(2, Int(360 * choice.window.frame.height / max(1, choice.window.frame.width)))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: choice.window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                windowPreviews[choice.id] = NSImage(cgImage: image, size: .zero)
            }
        }
    }
}

@MainActor
private final class ScreenIdentifiers {
    static let shared = ScreenIdentifiers()
    private var panels: [NSPanel] = []
    private var dismissTask: Task<Void, Never>?
    func show(_ screens: [NSScreen]) {
        hide()
        for (index, screen) in screens.enumerated() {
            let frame = NSRect(x: screen.frame.midX - 80, y: screen.frame.midY - 60, width: 160, height: 120)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: Text("\(index + 1)").font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white).frame(width: 160, height: 120)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 24)))
            panel.orderFrontRegardless(); panels.append(panel)
        }
        dismissTask = Task {
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            hide()
        }
    }
    func hide() {
        dismissTask?.cancel(); dismissTask = nil
        panels.forEach { $0.orderOut(nil) }; panels = []
    }
}
