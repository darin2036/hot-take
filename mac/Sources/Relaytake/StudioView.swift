import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI

/// The editor. Everything fits the window, with nothing to scroll: the preview takes whatever height is
/// left, and below it sit the transport, the timeline, and a bar for whatever is selected.
struct StudioView: View {
    let take: TakeEntry
    @ObservedObject var library: LibraryModel
    let close: () -> Void

    @StateObject private var model: StudioModel
    @FocusState private var focused: Bool
    @State private var showVoiceover = false
    @State private var showSuggestions = false
    @State private var confirmDiscard = false
    @State private var showSaveOptions = false
    @State private var originalBytes = 0

    // How copies are saved. Kept between sessions.
    @AppStorage("studioKeepOriginal") private var keepOriginal = true
    @AppStorage("studioQuality") private var sizeChoice = "medium"
    @AppStorage("studioIncludeAudio") private var includeAudio = true

    private var saveOptions: StudioSaveOptions {
        StudioSaveOptions(
            quality: keepOriginal ? nil : EncodingPreferences.resolve(VideoQuality(rawValue: sizeChoice) ?? .medium),
            includeAudio: includeAudio)
    }

    init(take: TakeEntry, library: LibraryModel, close: @escaping () -> Void) {
        self.init(model: StudioModel(take: take, library: library), close: close)
    }

    /// For rendering a prepared model (the --studio-snapshot check).
    init(model: StudioModel, close: @escaping () -> Void) {
        take = model.take
        library = model.library
        self.close = close
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            StudioPreview(model: model)
                .padding(.horizontal, 12)
                .frame(minHeight: 90, maxHeight: .infinity)
                .playbackControls(title: "Studio preview: \(take.title)", owner: model, library: library) {
                    AnyView(StudioStage(model: model))
                }
            Transport(model: model, clock: model.clock, showVoiceover: $showVoiceover, showSuggestions: $showSuggestions, take: take)
            TightenBar(model: model)
            StudioTimeline(model: model)
            StudioProperties(model: model, startVoiceover: { showVoiceover = true })
        }
        .overlay { if model.saveProgress != nil { savingOverlay } }
        .overlay(alignment: .top) { notice }
        .frame(minWidth: 520, minHeight: 480)
        .task { await model.load() }
        .onDisappear {
            model.shutdown()
            if library.openStudio === model { library.openStudio = nil }
            PlayerWindows.shared.closeAll(ownedBy: model)
            library.theater = nil
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true; library.openStudio = model }
        // Picking something on the timeline (or the picture) must also give the Studio the keyboard. Otherwise
        // Delete goes to whatever last had focus, such as a slider, or the library behind the Studio, where it
        // offers to trash the whole recording instead of removing the selected zoom, text or clip.
        .onChange(of: model.selection) { _, new in if new != .none, !Self.isTyping { focused = true } }
        // Studio shortcuts must never act on keys that are meant for a text field: space types a space,
        // delete erases a letter (not the selected clip), and escape belongs to the field.
        .onKeyPress(.space) { Self.isTyping ? .ignored : { model.togglePlay(); return .handled }() }
        .onKeyPress(.delete) { Self.isTyping ? .ignored : { model.deleteSelection(); return .handled }() }
        .onKeyPress(.deleteForward) { Self.isTyping ? .ignored : { model.deleteSelection(); return .handled }() }
        .onKeyPress(.escape) { Self.isTyping ? .ignored : { model.selection = .none; return .handled }() }
        // S (or ⌘B) splices at the playhead. [ and ] drop everything before or after the playhead in the part
        // it is in, for exact trims.
        .onKeyPress(KeyEquivalent("s"), phases: .down) { press in
            Self.isTyping || !press.modifiers.isEmpty ? .ignored : { model.splice(); return .handled }()
        }
        .onKeyPress("[") { Self.isTyping ? .ignored : { model.trimBeforePlayhead(); return .handled }() }
        .onKeyPress("]") { Self.isTyping ? .ignored : { model.trimAfterPlayhead(); return .handled }() }
        .confirmationDialog("Save your project before closing?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Save Project…") {
                model.shareProject { saved in if saved { model.discardDraft(); close() } }
            }
            Button("Discard Edits", role: .destructive) { model.discardDraft(); close() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save Project puts the recording and your edit in one file you can open later or hand to someone. Discard throws the edit away.")
        }
    }

    /// True while a text field (or any text editor) has the keyboard.
    static var isTyping: Bool { isTyping(in: NSApp.keyWindow ?? NSApp.mainWindow) }

    /// A text field being edited (or a text editor) makes the window's first responder a text view.
    static func isTyping(in window: NSWindow?) -> Bool { window?.firstResponder is NSTextView }

    // MARK: Pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { model.needsProjectSave ? (confirmDiscard = true) : { model.discardDraft(); close() }() } label: {
                Label("Done", systemImage: "chevron.left")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Studio").font(.headline)
                Text("Your original is never changed. Save Copy makes a new recording.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .labelStyle(.iconOnly).disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo").hoverLabel("Undo", above: false)
            Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .labelStyle(.iconOnly).disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo").hoverLabel("Redo", above: false)
            Button { showSaveOptions = true } label: { Label("Save Options", systemImage: "slider.horizontal.3") }
                .labelStyle(.iconOnly)
                .help("File size, audio, and exporting to a file")
                .hoverLabel("Save Options", above: false)
                .popover(isPresented: $showSaveOptions, arrowEdge: .bottom) { saveOptionsPanel }
            Button { model.save(options: saveOptions) { close() } } label: { Label("Save Copy", systemImage: "square.and.arrow.down") }
                .buttonStyle(TakeButtonStyle(color: .accentColor))
                .disabled(!model.canSave(saveOptions))
                .help(model.canSave(saveOptions)
                    ? "Make a new recording in your library. The original stays as it is."
                    : "Make an edit, or choose a smaller file size, first")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    /// File size, audio, and exporting to a file: everything the old Edit tab did when saving.
    private var saveOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save options").font(.headline)
            Toggle("Keep original quality", isOn: $keepOriginal)
                .help("Save at the quality of the recording. Turn off to make a smaller file.")
            if !keepOriginal {
                QualityPicker(value: $sizeChoice, seconds: model.project.outputDuration, audio: includeAudio)
            }
            Toggle("Include audio", isOn: $includeAudio)
                .help("Turn off for a silent video")
            if originalBytes > 0 {
                Text("Original: \(ByteCountFormatter.string(fromByteCount: Int64(originalBytes), countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Text("Export to a file").font(.subheadline.weight(.medium))
            Text("Saves wherever you choose and does not add it to your library.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(VideoExportFormat.allCases) { format in
                    Button(format.rawValue.uppercased()) {
                        showSaveOptions = false
                        model.export(format: format, options: saveOptions)
                    }
                    .disabled(!format.available || !model.ready)
                    .help(format.title)
                }
            }
            if !VideoExportFormat.webm.available {
                Text("WebM needs the optional FFmpeg encoder. MP4 and MOV work without it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 440)
        .task { originalBytes = (try? take.files.video.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
    }

    @ViewBuilder private var notice: some View {
        if !model.info.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(model.info).fixedSize(horizontal: false, vertical: true)
                Button("Dismiss") { model.info = "" }.buttonStyle(.link)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.separator))
            .padding(.top, 48)
        } else if !model.message.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                Text(model.message).fixedSize(horizontal: false, vertical: true)
                Button("Dismiss") { model.message = "" }.buttonStyle(.link)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.separator))
            .padding(.top, 48)
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 10) {
                Text(model.saveStatus).font(.headline)
                ProgressView(value: model.saveProgress ?? 0).frame(width: 260)
                Button("Cancel") { model.cancelSave() }
            }
            .padding(22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: Transport

private struct Transport: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var clock: StudioClock
    @Binding var showVoiceover: Bool
    @Binding var showSuggestions: Bool
    let take: TakeEntry

    @State private var showCaptions = false
    @State private var showBackground = false
    @State private var showCamera = false
    @State private var showZoom = false
    @State private var showMarks = false
    @AppStorage("autoZoomAmount") private var zoomAmount = 1.8
    @AppStorage("tightenPause") private var pauseSeconds = 2.0
    @State private var fromPlayhead = false
    @State private var replaceOriginal = true

    var body: some View {
        HStack(spacing: 10) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
            }
            .help("Play or pause (Space)")
            .hoverLabel(model.isPlaying ? "Pause" : "Play")
            .disabled(!model.ready)
            Text("\(timeLabel(clock.time)) / \(timeLabel(model.project.outputDuration))")
                .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
            Menu {
                // Choosing a mode splices with it and becomes what the button itself does from now on.
                ForEach(StudioModel.SpliceTarget.allCases, id: \.self) { mode in
                    Button(mode.title, systemImage: mode.symbol) { model.spliceMode = mode; model.splice(mode) }
                        .help(mode.help)
                }
            } label: {
                Label("Splice \(model.spliceTarget)", systemImage: model.spliceSymbol)
            } primaryAction: {
                model.splice()
            }
            .fixedSize()
            .keyboardShortcut("b", modifiers: .command)
            .help("Break the track you have selected at the playhead (S or ⌘B): the Audio track, or a text, zoom, music or voiceover clip. With nothing selected it breaks every track, video and sound together. The arrow beside it picks the video or the audio alone, and the button then keeps that choice. [ and ] drop everything before or after the playhead.")
            .disabled(!model.ready)

            Spacer(minLength: 8)

            if model.voice == .recording {
                Button { model.finishVoiceover() } label: { Label("Stop Recording", systemImage: "stop.circle.fill") }
                    .buttonStyle(TakeButtonStyle(color: .red))
            } else if case .countdown = model.voice {
                Button("Cancel") { model.cancelVoiceover() }
            } else {
                // All four tools show their names when there is room, or all show icons only.
                ViewThatFits(in: .horizontal) {
                    tools(iconOnly: false).labelStyle(.titleAndIcon)
                    tools(iconOnly: true).labelStyle(.iconOnly)
                }
            }
        }
        .disabled(model.saveProgress != nil)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// With `iconOnly`, each tool gets a hover label with its name, since the name is not on screen.
    private func tools(iconOnly: Bool) -> some View {
        HStack(spacing: 10) {
            Button { model.addText() } label: { Label("Add Text", systemImage: "textformat").imageScale(.large) }
                .help("Put words on the video at the playhead")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Add Text" : nil)
            Button { showCaptions = true } label: {
                Label("Captions", systemImage: model.project.captions == nil ? "captions.bubble" : "captions.bubble.fill")
            }
            .help("Draw the speech on the video as captions")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Captions" : nil)
            .popover(isPresented: $showCaptions, arrowEdge: .top) { captionOptions }
            Button { showBackground = true } label: {
                Label("Background", systemImage: model.project.background == nil ? "rectangle.inset.filled" : "rectangle.inset.filled.and.person.filled")
            }
            .help("Put the recording on a styled backdrop, with the window rounded and inset")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Background" : nil)
            .popover(isPresented: $showBackground, arrowEdge: .top) { backgroundOptions }
            if model.project.cameraSource != nil {
                Button { showCamera = true } label: {
                    Label("Presenter", systemImage: model.project.camera.isVisible ? "person.crop.circle.fill" : "person.crop.circle")
                }
                .help("Move, resize or hide the presenter")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Presenter" : nil)
                .popover(isPresented: $showCamera, arrowEdge: .top) { cameraOptions }
            }
            Button { showZoom = true } label: { Label("Auto Zoom", systemImage: "plus.magnifyingglass") }
                .help("Zoom in on your clicks")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Auto Zoom" : nil)
                .popover(isPresented: $showZoom, arrowEdge: .top) { zoomOptions }
            Button { showMarks = true } label: {
                Label("Mark", systemImage: model.project.shapes.isEmpty && model.project.clickHighlight == nil ? "pencil.tip.crop.circle" : "pencil.tip.crop.circle.fill")
            }
            .help("Draw an arrow, box or blur on the picture, or ring your clicks")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Mark" : nil)
                .popover(isPresented: $showMarks, arrowEdge: .top) { markOptions }
            Button { model.chooseMusic() } label: { Label("Add Music", systemImage: "music.note") }
                .help("Choose a song to play under the video. You can also drop an audio file on the timeline.")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Add Music" : nil)
            Button { showVoiceover = true } label: { Label("Voiceover", systemImage: "mic") }
                .help("Record your voice over the video")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Voiceover" : nil)
                .popover(isPresented: $showVoiceover, arrowEdge: .top) { voiceoverOptions }
            Button { showSuggestions = true } label: { Label("Tighten", systemImage: "wand.and.stars") }
                .help("Find long pauses and restarts you may want to cut")
                .frame(width: iconOnly ? 34 : nil, height: iconOnly ? 26 : nil)
                .hoverLabel(iconOnly ? "Tighten" : nil, anchor: .trailing)
                .popover(isPresented: $showSuggestions, arrowEdge: .top) { tightenPanel }
        }
    }

    /// Finds pauses and restarts. They then sit on the Video track for you to cut one by one, or all the pauses at once.
    private var tightenPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tighten").font(.headline)
            Text("Finds long pauses and places where you said something twice. They show on the Video track, and nothing is cut until you choose it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Pauses longer than").font(.caption).foregroundStyle(.secondary)
                Picker("Pauses longer than", selection: $pauseSeconds) {
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("3 s").tag(3.0)
                }
                .pickerStyle(.segmented).labelsHidden()
                .help("Pauses shorter than this are left alone. A little breathing room stays at each end of a pause you cut.")
            }
            HStack(spacing: 10) {
                Button(model.tightenSearched ? "Find Again" : "Find Pauses and Restarts") {
                    model.findTighten(pauseLength: pauseSeconds) { found in if found > 0 { showSuggestions = false } }
                }
                .disabled(model.tightenStatus != nil)
                if let status = model.tightenStatus {
                    ProgressView().controlSize(.small)
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if model.tightenSearched, model.pendingTighten.isEmpty, model.tightenStatus == nil {
                Label("Nothing to tighten. No long pauses or repeated sentences were found.", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.tightenNotes, id: \.self) {
                Text($0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(width: 340)
    }

    private var backgroundOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.headline)
            Toggle("Show a background behind the recording", isOn: Binding(
                get: { model.project.background != nil }, set: { model.setBackgroundOn($0) }))
            if model.captureKind == "window" {
                Text("This was a window recording, so the window sits on the backdrop without your menu bar or desktop around it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let background = model.project.background {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 6), spacing: 8) {
                    ForEach(WindowBackground.presets) { preset in
                        Button { model.changeBackground { $0.top = preset.top; $0.bottom = preset.bottom } } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [preset.top.color, preset.bottom.color], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 44, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                                    Color.accentColor, lineWidth: background.top == preset.top && background.bottom == preset.bottom ? 2.5 : 0))
                        }.buttonStyle(.plain).help(preset.name).accessibilityLabel(preset.name)
                    }
                }
                HStack {
                    ColorPicker("Solid color", selection: Binding(
                        get: { background.top.color },
                        set: { new in
                            let color = TextColor(NSColor(new))
                            model.changeBackground(coalescing: "bgcolor") { $0.top = color; $0.bottom = color }
                        }), supportsOpacity: false)
                    Spacer()
                }
                slider("Margin", value: Binding(
                    get: { background.padding },
                    set: { value in model.changeBackground(coalescing: "bgpad") { $0.padding = value } }),
                    range: WindowBackground.paddingRange)
                slider("Rounded corners", value: Binding(
                    get: { background.cornerRadius },
                    set: { value in model.changeBackground(coalescing: "bgcorner") { $0.cornerRadius = value } }),
                    range: WindowBackground.cornerRange)
                Toggle("Shadow", isOn: Binding(get: { background.shadow }, set: { on in model.changeBackground { $0.shadow = on } }))
                Text("The backdrop is drawn into the picture when you save a copy. Your original is never changed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(width: 320)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range)
        }
    }

    private var cameraOptions: some View {
        let camera = model.project.camera
        return VStack(alignment: .leading, spacing: 12) {
            Text("Presenter").font(.headline)
            Toggle("Show the presenter", isOn: Binding(get: { camera.isVisible }, set: { on in model.setCamera { $0.isVisible = on } }))
            if camera.isVisible {
                HStack {
                    Text("Corner").frame(width: 70, alignment: .leading)
                    ForEach(CameraCorner.allCases) { corner in
                        Button { model.setCamera { $0.corner = corner } } label: { cornerIcon(corner, selected: camera.corner == corner) }
                            .buttonStyle(.plain).help(corner.title).accessibilityLabel(corner.title)
                    }
                    Spacer()
                }
                Text("Or drag it in the preview.").font(.caption).foregroundStyle(.secondary)
                Picker("Shape", selection: Binding(get: { camera.shape }, set: { shape in model.setCamera { $0.shape = shape } })) {
                    ForEach(CameraShape.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                slider("Size", value: Binding(get: { camera.size }, set: { value in model.setCamera(coalescing: "camsize") { $0.size = value } }),
                       range: CameraBubble.sizeRange)
                Toggle("Border", isOn: Binding(get: { camera.hasBorder }, set: { on in model.setCamera { $0.hasBorder = on } }))
                Toggle("Mirror", isOn: Binding(get: { camera.isMirrored }, set: { on in model.setCamera { $0.isMirrored = on } }))
                    .help("Flip the camera left to right, like a mirror. Off shows you the way others see you.")
                Stepper(value: Binding(get: { camera.nudge }, set: { value in model.setCamera(coalescing: "camnudge") { $0.nudge = value } }),
                        in: CameraBubble.nudgeRange, step: 0.05) {
                    Text("Line up: \(camera.nudge >= 0 ? "+" : "")\(String(format: "%.2f", camera.nudge)) s").monospacedDigit()
                }
                .help("If the camera is a little ahead of or behind the screen, nudge it. Positive delays the camera.")
                Text("The camera is drawn into the picture when you save a copy. The recording itself is not changed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(width: 330)
    }

    /// A tiny picture of the screen with a dot in the corner.
    private func cornerIcon(_ corner: CameraCorner, selected: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).stroke(selected ? Color.accentColor : .secondary, lineWidth: selected ? 2 : 1)
            Circle().fill(selected ? Color.accentColor : .secondary).frame(width: 7, height: 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: {
                    switch corner {
                    case .topLeft: .topLeading
                    case .topRight: .topTrailing
                    case .bottomLeft: .bottomLeading
                    case .bottomRight: .bottomTrailing
                    }
                }())
                .padding(3)
        }
        .frame(width: 28, height: 20)
    }

    private var zoomOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Auto Zoom").font(.headline)
            if model.clicks.isEmpty {
                Text("No clicks were noted for this recording, so there is nothing to zoom in on automatically. You can still add a zoom by hand.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(model.clicks.count) click\(model.clicks.count == 1 ? "" : "s") were noted while recording. Clicks close together share one zoom.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Zoom in").frame(width: 70, alignment: .leading)
                Slider(value: $zoomAmount, in: ZoomSegment.scaleRange)
                Text(String(format: "%.1f×", zoomAmount)).monospacedDigit().frame(width: 40)
            }
            HStack {
                Button("Zoom In on My Clicks") { model.generateZooms(scale: zoomAmount); showZoom = false }
                    .disabled(model.clicks.isEmpty)
                Button("Add One Here") { model.addZoom(); showZoom = false }
                Spacer()
                if !model.project.zooms.isEmpty {
                    Button("Remove All", role: .destructive) { model.edit { $0.zooms = [] }; model.selection = .none }
                }
            }
            Text("Each zoom shows on the Zoom track. Drag it to move, drag its ends to resize, click it to change how far it zooms, and click the video to point it. Zooms are drawn in when you save a copy.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(width: 340)
    }

    /// Arrows, boxes and blurs, and rings at the clicks noted while recording.
    private var markOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mark").font(.headline)
            Text("Add one at the playhead, then drag its handles on the picture to put it where you want. Marks stay on what they point at when the picture zooms, and are drawn in when you save a copy.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ForEach(ShapeOverlay.Kind.allCases, id: \.self) { kind in
                    Button { model.addShape(kind); showMarks = false } label: { Label(kind.title, systemImage: kind.symbol) }
                        .help(kind == .blur ? "Blur out a region, such as a name or an email address" : "Add a \(kind.title.lowercased())")
                }
            }
            Divider()
            Toggle("Ring each click", isOn: Binding(
                get: { model.project.clickHighlight != nil }, set: { model.setClickHighlightsOn($0) }))
                .disabled(model.clicks.isEmpty)
                .help("A ring opens where the mouse was clicked while recording")
            if model.clicks.isEmpty {
                Text("No clicks were noted for this recording.").font(.caption).foregroundStyle(.secondary)
            } else if let highlight = model.project.clickHighlight {
                HStack(spacing: 8) {
                    Text("Color").frame(width: 60, alignment: .leading)
                    ForEach(Array(TextColor.presets.prefix(7).enumerated()), id: \.offset) { _, preset in
                        swatch(preset.color, name: preset.name, selected: highlight.color == preset.color) {
                            model.changeClickHighlight { $0.color = preset.color }
                        }
                    }
                }
                HStack {
                    Text("Size").frame(width: 60, alignment: .leading)
                    Slider(value: Binding(
                        get: { highlight.size },
                        set: { value in model.changeClickHighlight(coalescing: "ringsize") { $0.size = value } }),
                        in: ClickHighlight.sizeRange)
                }
                Text("\(highlight.clicks.count) click\(highlight.clicks.count == 1 ? "" : "s") noted. A click in a section you cut out has no ring.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(width: 340)
    }

    private var captionOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captions").font(.headline)
            Toggle("Show captions in the video", isOn: Binding(
                get: { model.project.captions != nil }, set: { model.setCaptionsOn($0) }))
                .disabled(model.captionStatus != nil)
                .help("Captions are drawn into the picture, so they show in any player. They come from the recording's transcript.")
            if let status = model.captionStatus {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            if let captions = model.project.captions {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(CaptionStyle.allCases) { style in
                        Button { model.setCaptionStyle(style) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: captions.style == style ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(captions.style == style ? Color.accentColor : .secondary)
                                captionSample(style)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(style.title).font(.callout.weight(.medium))
                                    Text(style.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                Picker("Position", selection: Binding(get: { captions.position }, set: { model.setCaptionPosition($0) })) {
                    ForEach(CaptionPosition.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if !model.captionTranslations.isEmpty {
                    Picker("Language", selection: Binding(get: { captions.language }, set: { model.setCaptionLanguage($0) })) {
                        Text("As spoken").tag(String?.none)
                        ForEach(model.captionTranslations, id: \.self) { Text(CaptionTranslator.name(for: $0)).tag(Optional($0)) }
                    }
                    .help("Translations are made on the Transcript tab.")
                }
                Text("Saved into the picture when you save a copy, so they can't be turned off afterward. Your original is never changed.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(width: 340)
    }

    /// A small "Aa" showing the style.
    private func captionSample(_ style: CaptionStyle) -> some View {
        let line = style.sampleOverlay
        return Text("Aa")
            .font(Font(line.nsFont(pointSize: 15) as CTFont))
            .foregroundStyle(line.color.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background {
                if line.showsBackground { RoundedRectangle(cornerRadius: 5).fill(line.boxColor.color.opacity(0.75)) }
            }
            .shadow(color: line.showsBackground ? .clear : .black.opacity(0.8), radius: 2)
            .frame(width: 52, height: 30)
            .background(Color.gray.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
    }

    private var voiceoverOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record a voiceover").font(.headline)
            Text("The video plays with its own sound muted while you talk. Use headphones so the microphone doesn't hear it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            MicrophonePicker()
            Picker("Start", selection: $fromPlayhead) {
                Text("From the beginning").tag(false)
                Text("From the playhead (\(timeLabel(clock.time)))").tag(true)
            }
            .pickerStyle(.radioGroup)
            Toggle("Replace the original audio with my voice", isOn: $replaceOriginal)
            HStack {
                Spacer()
                Button("Cancel") { showVoiceover = false }
                Button("Start Recording") {
                    showVoiceover = false
                    model.startVoiceover(fromPlayhead: fromPlayhead, replaceOriginal: replaceOriginal)
                }
                .buttonStyle(TakeButtonStyle(color: .red))
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: What is selected

struct StudioProperties: View {
    @ObservedObject var model: StudioModel
    let startVoiceover: () -> Void
    @State private var showStyle = false

    var body: some View {
        HStack(spacing: 14) { content }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading)
            .background(.bar)
    }

    @ViewBuilder private var content: some View {
        switch model.selection {
        case .none:
            Label("Click a clip to change it. To cut, move the playhead and Splice (S) to break every track, or select the Audio track first to break only the sound. Then click a part and press Delete.", systemImage: "hand.point.up.left")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
        case .range(let range): rangeBar(range)
        case .text(let id):
            if let text = model.project.text(id) { textBar(text) }
        case .zoom(let id):
            if let zoom = model.project.zoom(id) { zoomBar(zoom) }
        case .shape(let id):
            if let shape = model.project.shape(id) { shapeBar(shape) }
        case .clip(let id):
            if let clip = model.project.clip(id) { clipBar(clip) }
        case .original: originalBar(part: nil)
        case .audioPart(let id): originalBar(part: model.project.originalAudioPart(id))
        }
    }

    // A section of the picture
    private func rangeBar(_ range: TimeSpan) -> some View {
        let parts = model.project.cuts.partSpans
        let partNumber = parts.firstIndex { abs($0.start - range.start) < 0.01 && abs($0.end - range.end) < 0.01 }.map { $0 + 1 }
        return HStack(spacing: 12) {
            Image(systemName: "scissors")
            Text((partNumber.map { "Part \($0) of \(parts.count)  ·  " } ?? "")
                + "\(timeLabel(range.start)) – \(timeLabel(range.end))  ·  \(String(format: "%.1f", range.length)) s")
                .monospacedDigit()
            Spacer()
            Button("Remove") { model.removeSection(range) }
                .help("Take this out of the video (Delete)")
            Button("Keep Only This") { model.keepOnly(range) }
                .help("Remove everything except this")
            Button("Clear") { model.selection = .none }
        }
    }

    // Text
    private func textBar(_ text: TextOverlay) -> some View {
        let id = text.id
        return HStack(spacing: 12) {
            TextField("Your text", text: Binding(
                get: { model.project.text(id)?.text ?? "" },
                set: { value in model.edit(coalescing: "text-\(id)") { $0.updateText(id) { $0.text = value } } }))
                .textFieldStyle(.roundedBorder).frame(minWidth: 120, idealWidth: 240)
            Button { showStyle = true } label: { Label("Style", systemImage: "textformat") }
                .help("Font, size, color and box")
                .popover(isPresented: $showStyle, arrowEdge: .top) { TextStylePanel(model: model, id: id) }
            HStack(spacing: 6) {
                ForEach(Array(TextColor.presets.prefix(5).enumerated()), id: \.offset) { _, preset in
                    swatch(preset.color, name: preset.name, selected: text.color == preset.color) {
                        model.edit { $0.updateText(id) { $0.color = preset.color } }
                    }
                }
            }
            Stepper(value: Binding(
                get: { text.length }, set: { value in model.edit(coalescing: "len-\(id)") { $0.updateText(id) { $0.end = $0.start + value } } }),
                in: 0.3...max(0.3, model.project.outputDuration), step: 0.5) {
                Text("\(String(format: "%.1f", text.length)) s").monospacedDigit()
            }
            .help("How long the text stays on screen")
            Spacer(minLength: 0)
            Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }.help("Delete this text").hoverLabel("Delete Text", anchor: .trailing)
        }
    }

    // A zoom
    private func zoomBar(_ zoom: ZoomSegment) -> some View {
        let id = zoom.id
        return HStack(spacing: 12) {
            Image(systemName: "plus.magnifyingglass")
            Text("Zoom").fontWeight(.semibold)
            Slider(value: Binding(
                get: { zoom.scale }, set: { value in model.edit(coalescing: "zoom-\(id)") { $0.updateZoom(id) { $0.scale = value } } }),
                in: ZoomSegment.scaleRange)
                .frame(width: 120).help("How far it zooms in")
            Text(String(format: "%.1f×", zoom.scale)).monospacedDigit().frame(width: 40, alignment: .leading).foregroundStyle(.secondary)
            Stepper(value: Binding(
                get: { zoom.length }, set: { value in model.edit(coalescing: "zlen-\(id)") { $0.updateZoom(id) { $0.end = $0.start + value } } }),
                in: ZoomSegment.minimumLength...max(ZoomSegment.minimumLength, model.project.outputDuration), step: 0.5) {
                Text("\(String(format: "%.1f", zoom.length)) s").monospacedDigit()
            }
            .help("How long the zoom lasts, including easing in and out")
            Text("Click the video to point the zoom").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }.help("Remove this zoom").hoverLabel("Remove Zoom", anchor: .trailing)
        }
    }

    // An arrow, box or blur
    private func shapeBar(_ shape: ShapeOverlay) -> some View {
        let id = shape.id
        return HStack(spacing: 12) {
            Image(systemName: shape.kind.symbol)
            Text(shape.kind.title).fontWeight(.semibold)
            if shape.kind != .blur {
                HStack(spacing: 6) {
                    ForEach(Array(TextColor.presets.prefix(7).enumerated()), id: \.offset) { _, preset in
                        swatch(preset.color, name: preset.name, selected: shape.color == preset.color) {
                            model.changeShape(id) { $0.color = preset.color }
                        }
                    }
                }
                Slider(value: Binding(
                    get: { shape.lineWidth },
                    set: { value in model.changeShape(id, coalescing: "line-\(id)") { $0.lineWidth = value } }),
                    in: ShapeOverlay.lineWidthRange)
                    .frame(width: 100).help("How thick the line is")
            } else {
                Slider(value: Binding(
                    get: { shape.blurRadius },
                    set: { value in model.changeShape(id, coalescing: "blur-\(id)") { $0.blurRadius = value } }),
                    in: ShapeOverlay.blurRange)
                    .frame(width: 140).help("How strongly it blurs")
            }
            Stepper(value: Binding(
                get: { shape.length },
                set: { value in model.changeShape(id, coalescing: "slen-\(id)") { $0.end = $0.start + value } }),
                in: ShapeOverlay.minimumLength...max(ShapeOverlay.minimumLength, model.project.outputDuration), step: 0.5) {
                Text("\(String(format: "%.1f", shape.length)) s").monospacedDigit()
            }
            .help("How long it stays on screen")
            Text("Drag the handles on the picture").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }.help("Remove this mark").hoverLabel("Remove Mark", anchor: .trailing)
        }
    }

    // Music or voiceover
    private func clipBar(_ clip: AudioClip) -> some View {
        let id = clip.id
        return HStack(spacing: 12) {
            Image(systemName: clip.kind == .music ? "music.note" : "mic")
            Text(clip.name).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
            Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { clip.volume }, set: { value in model.edit(coalescing: "vol-\(id)") { $0.updateClip(id) { $0.volume = value } } }),
                in: 0...1.5)
                .frame(width: 110).help("Volume")
            Text("\(Int(clip.volume * 100))%").monospacedDigit().frame(width: 40, alignment: .leading).foregroundStyle(.secondary)
            // Fixed size, so a label never wraps letter by letter when the bar is crowded.
            Toggle("Fade in", isOn: Binding(get: { clip.fadeIn > 0 }, set: { on in model.edit { $0.updateClip(id) { $0.fadeIn = on ? 0.5 : 0 } } }))
                .fixedSize()
            Toggle("Fade out", isOn: Binding(get: { clip.fadeOut > 0 }, set: { on in model.edit { $0.updateClip(id) { $0.fadeOut = on ? 1.5 : 0 } } }))
                .fixedSize()
            if clip.kind == .music {
                Toggle("Fit to video", isOn: Binding(get: { clip.fitsVideo }, set: { on in
                    model.edit { $0.updateClip(id) { $0.fitsVideo = on; if on { $0.loops = true } } }
                }))
                .fixedSize()
                .help("Play for the whole video, repeating the song if it is short")
            }
            Spacer(minLength: 0)
            if clip.kind == .music {
                Button("Replace…") { model.chooseMusic() }
            } else {
                MicrophonePicker(compact: true)
                Button("Re-record") { startVoiceover() }
            }
            Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }.help("Remove this track").hoverLabel("Remove Track", anchor: .trailing)
        }
    }

    // The recording's own sound
    private func originalBar(part: OriginalAudioPart?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
            Text(part.map { "Audio part  ·  \(timeLabel($0.start)) – \(timeLabel($0.end))" } ?? "Original audio")
            Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { model.project.originalVolume },
                set: { value in model.edit(coalescing: "original") { $0.originalVolume = value } }), in: 0...1.5)
                .frame(width: 160)
            Text("\(Int(model.project.originalVolume * 100))%").monospacedDigit().frame(width: 44, alignment: .leading).foregroundStyle(.secondary)
            Toggle("Mute", isOn: Binding(
                get: { model.project.originalVolume == 0 },
                set: { muted in model.edit { $0.originalVolume = muted ? 0 : 1 } }))
            Text("Splice (S) cuts only this sound.").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let part, let index = model.project.audioParts?.firstIndex(where: { $0.id == part.id }) {
                if model.project.isOriginalAudioSplice(afterPart: index - 1) {
                    Button("Join Previous") { model.removeAudioSplice(afterPart: index - 1) }
                        .help("Undo the splice before this part")
                }
                if model.project.isOriginalAudioSplice(afterPart: index) {
                    Button("Join Next") { model.removeAudioSplice(afterPart: index) }
                        .help("Undo the splice after this part")
                }
                Button("Remove") { model.deleteSelection() }
                    .help("Take this sound out and leave silence; the picture stays (Delete)")
            }
            if !model.project.originalAudioFollowsVideo {
                Button("Follow Video") { model.relinkOriginalAudio() }
                    .help("Undo the cuts made to the audio alone, so it is cut wherever the video is")
            }
        }
    }
}

/// Which microphone to record the voiceover with. The choice is remembered; "Default" follows the
/// Mac's current input, which is also what you get if the microphone you picked is unplugged.
struct MicrophonePicker: View {
    var compact = false
    @AppStorage("voiceoverMicrophone") private var chosen = ""
    @State private var microphones = Microphone.available()

    var body: some View {
        let picker = Picker("Microphone", selection: $chosen) {
            ForEach(microphones) { Text($0.name).tag($0.id) }
            if !chosen.isEmpty && !microphones.contains(where: { $0.id == chosen }) {
                Text("Chosen microphone (not connected)").tag(chosen)
            }
        }
        .onAppear { microphones = Microphone.available() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in microphones = Microphone.available() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in microphones = Microphone.available() }

        if compact {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").foregroundStyle(.secondary)
                picker.labelsHidden().frame(width: 190)
            }
            .help("Microphone for the next voiceover")
        } else {
            picker
        }
    }
}

/// A round color swatch; the chosen one gets a ring.
@ViewBuilder
func swatch(_ color: TextColor, name: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Circle().fill(color.color).frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: selected ? 3 : 0).padding(-3))
    }
    .buttonStyle(.plain)
    .help(name)
    .accessibilityLabel(name)
}

/// Everything about how a piece of text looks. Changes apply as you make them and can be undone.
struct TextStylePanel: View {
    @ObservedObject var model: StudioModel
    let id: UUID

    var body: some View {
        if let text = model.project.text(id) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Text style").font(.headline)

                row("Font") {
                    Picker("Font", selection: Binding(
                        get: { text.fontFamily }, set: { value in change { $0.fontFamily = value } })) {
                        ForEach(TextOverlay.fontFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().frame(width: 190)
                    Toggle(isOn: Binding(get: { text.isBold }, set: { value in change { $0.isBold = value } })) {
                        Image(systemName: "bold")
                    }
                    .toggleStyle(.button).help("Bold").hoverLabel("Bold")
                    Toggle(isOn: Binding(get: { text.isItalic }, set: { value in change { $0.isItalic = value } })) {
                        Image(systemName: "italic")
                    }
                    .toggleStyle(.button).help("Italic").hoverLabel("Italic")
                }

                row("Size") {
                    Picker("Size", selection: Binding(
                        get: { text.sizePreset }, set: { value in if let value { change { $0.heightFraction = value.heightFraction } } })) {
                        ForEach(TextOverlay.Size.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        if text.sizePreset == nil { Text("–").tag(Optional<TextOverlay.Size>.none) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                    Slider(value: Binding(get: { text.heightFraction }, set: { value in change { $0.heightFraction = value } }),
                           in: TextOverlay.sizeRange)
                        .frame(width: 110).help("Any size in between")
                }

                row("Color") {
                    VStack(alignment: .leading, spacing: 8) {
                        palette(selected: text.color) { color in change { $0.color = color } }
                        ColorPicker("Custom color", selection: Binding(
                            get: { text.color.color }, set: { value in change { $0.color = TextColor(value) } }), supportsOpacity: false)
                    }
                }

                row("Box") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show a box behind the text", isOn: Binding(
                            get: { text.showsBackground }, set: { value in change { $0.showsBackground = value } }))
                        if text.showsBackground {
                            palette(selected: text.boxColor, colors: [("Black", .black), ("White", .white)] + Array(TextColor.presets.dropFirst().dropLast())) { color in
                                change { $0.boxColor = color }
                            }
                            ColorPicker("Custom box color", selection: Binding(
                                get: { text.boxColor.color }, set: { value in change { $0.boxColor = TextColor(value) } }), supportsOpacity: false)
                        } else {
                            Text("Without a box the words get a soft shadow instead.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(width: 400)
        }
    }

    private func change(_ edit: @escaping (inout TextOverlay) -> Void) {
        model.edit(coalescing: "style-\(id)") { $0.updateText(id, edit) }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).foregroundStyle(.secondary).frame(width: 48, alignment: .leading).padding(.top, 3)
            HStack(alignment: .top, spacing: 8) { content() }
        }
    }

    private func palette(
        selected: TextColor, colors: [(name: String, color: TextColor)] = TextColor.presets, pick: @escaping (TextColor) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, preset in
                swatch(preset.color, name: preset.name, selected: selected == preset.color) { pick(preset.color) }
            }
        }
    }
}

/// A thin strip above the timeline while there are pauses or restarts to review.
private struct TightenBar: View {
    @ObservedObject var model: StudioModel

    private func plural(_ count: Int, _ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }

    @ViewBuilder var body: some View {
        let pending = model.pendingTighten
        if !pending.isEmpty {
            let pauses = pending.filter { $0.kind == .silence }
            let restarts = pending.count - pauses.count
            let pauseTime = pauses.reduce(0.0) { $0 + $1.span.length }
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").foregroundStyle(.orange)
                Text(([pauses.isEmpty ? nil : plural(pauses.count, "pause"), restarts == 0 ? nil : plural(restarts, "restart")]
                    .compactMap { $0 }.joined(separator: " and ")) + " to review. Hover one on the Video track to cut it or keep it.")
                    .font(.callout).lineLimit(1)
                Spacer(minLength: 8)
                if !pauses.isEmpty {
                    Button("Cut All Pauses (\(String(format: "%.1f", pauseTime)) s)") { model.cutTighten(pauses) }
                        .help("Cut every pause out in one step. Restarts are always cut one at a time. You can undo it.")
                }
                Button("Clear") { model.clearTighten() }
                    .help("Remove these suggestions from the timeline without cutting anything")
            }
            .controlSize(.small)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Color.orange.opacity(0.1))
        }
    }
}
