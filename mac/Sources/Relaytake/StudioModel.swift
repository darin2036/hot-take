import AVFoundation
import AppKit
import Combine
import Foundation
import RelaytakeCore
import UniformTypeIdentifiers

/// The playhead, kept apart from the rest of the model so that only the views that need the current
/// time (playhead, text preview, time label) redraw as it ticks.
final class StudioClock: ObservableObject {
    @Published var time = 0.0
}

/// Drives the Studio: the project being edited, playback of the edited result, undo, recording a
/// voiceover, and saving. The original recording is only ever read.
@MainActor
final class StudioModel: ObservableObject {
    enum Selection: Equatable {
        case none
        /// A section of the Video track chosen by dragging, waiting to be removed or kept.
        case range(TimeSpan)
        case text(UUID)
        case zoom(UUID)
        case clip(UUID)
        case original
    }

    enum VoiceState: Equatable {
        case idle
        case countdown(Int)
        case recording
    }

    let take: TakeEntry
    let library: LibraryModel
    let player = AVPlayer()
    private let asset: AVURLAsset
    var sourceAsset: AVAsset { asset }

    @Published private(set) var project = StudioProject(duration: 0)
    @Published var selection: Selection = .none
    /// Playhead, in seconds of the edited video.
    let clock = StudioClock()
    var time: Double {
        get { clock.time }
        set { clock.time = newValue }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var ready = false
    @Published private(set) var videoSize = CGSize(width: 16, height: 9)
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var message = ""
    /// A good-news note, such as where an export went.
    @Published var info = ""

    @Published private(set) var voice = VoiceState.idle
    @Published private(set) var inputLevel = 0.0

    /// Loudness over time per audio file, for drawing waveforms.
    @Published private(set) var levels: [URL: [Double]] = [:]

    /// Progress of saving, 0...1, or nil when not saving.
    @Published private(set) var saveProgress: Double?
    @Published private(set) var saveStatus = ""

    private var history = UndoStack<StudioProject>()
    private var gestureBase: StudioProject?
    private var lastCoalesceKey: String?
    private var lastCoalesceTime = Date.distantPast
    private var rebuildTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    private var recorder: MicrophoneRecorder?
    private var meterTimer: Timer?
    private var voiceStart = 0.0
    private var voiceReplacesOriginal = true
    private var voiceTask: Task<Void, Never>?

    init(take: TakeEntry, library: LibraryModel) {
        self.take = take
        self.library = library
        // A take recorded with a camera has its camera drawn in already; the Studio goes back to the originals so
        // the camera can be moved, resized or hidden.
        let hasOriginals = FileManager.default.fileExists(atPath: take.files.screenOriginal.path)
        asset = AVURLAsset(url: hasOriginals ? take.files.screenOriginal : take.files.video)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.04, preferredTimescale: 600), queue: .main) { [weak self] value in
            MainActor.assumeIsolated {
                guard let self, value.seconds.isFinite else { return }
                self.time = min(value.seconds, self.project.outputDuration)
            }
        }
        player.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main).sink { [weak self] status in
            self?.isPlaying = status != .paused
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if self.voice == .recording { self.finishVoiceover() }
        }.store(in: &cancellables)
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.pause()
    }

    var hasUnsavedChanges: Bool { project.isEdited }

    // MARK: Loading

    func load() async {
        guard !ready else { return }  // the view's own load must not wipe edits made before it appeared
        do {
            let duration = try await asset.load(.duration).seconds
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let natural = try await track.load(.naturalSize)
                let rect = CGRect(origin: .zero, size: natural).applying(try await track.load(.preferredTransform))
                videoSize = CGSize(width: max(1, abs(rect.width)), height: max(1, abs(rect.height)))
            }
            project = StudioProject(duration: duration, cameraSource: cameraSource())
            loadCapture()
            ready = true
            loadLevels(for: take.files.video)
            await rebuildPreview()
        } catch {
            message = "This recording could not be opened for editing: \(error.localizedDescription)"
        }
    }

    func loadLevels(for url: URL) {
        guard levels[url] == nil else { return }
        Task {
            if let result = try? await AudioLevels.analyze(url: url) { levels[url] = result }
        }
    }

    // MARK: Background and zoom

    /// Clicks seen while recording, and what was captured ("screen", "window" or "area"). Empty for
    /// recordings made before clicks were noted.
    @Published private(set) var clicks: [ClickEvent] = []
    @Published private(set) var captureKind: String?

    /// The camera recording that goes with this take, when it was recorded with one and the originals are still there.
    private func cameraSource() -> CameraSource? {
        let files = take.files
        let metadata = TakeLibrary.metadata(for: files)
        guard let offset = metadata?.cameraOffset,
              FileManager.default.fileExists(atPath: files.cameraOriginal.path),
              FileManager.default.fileExists(atPath: files.screenOriginal.path)
        else { return nil }
        return CameraSource(url: files.cameraOriginal, offset: offset, placement: metadata?.cameraPlacement)
    }

    func setCamera(coalescing key: String? = nil, _ change: @escaping (inout CameraBubble) -> Void) {
        edit(coalescing: key) { project in
            change(&project.camera)
            project.camera.clamp()
        }
    }

    func loadCapture() {
        let metadata = TakeLibrary.metadata(for: take.files)
        clicks = metadata?.clicks ?? []
        captureKind = metadata?.captureKind
    }

    /// Turns the backdrop on (with the standard look) or off.
    func setBackgroundOn(_ on: Bool) { edit { $0.background = on ? ($0.background ?? .standard) : nil } }
    func changeBackground(coalescing key: String? = nil, _ change: (inout WindowBackground) -> Void) {
        edit(coalescing: key) { project in
            guard var background = project.background else { return }
            change(&background)
            project.background = WindowBackground(
                top: background.top, bottom: background.bottom, padding: background.padding,
                cornerRadius: background.cornerRadius, shadow: background.shadow)
        }
    }

    /// Proposes zooms from the recorded clicks, replacing the current ones.
    func generateZooms(scale: Double) {
        guard !clicks.isEmpty else { return }
        edit { $0.generateZooms(from: self.clicks, scale: scale) }
        if project.zooms.isEmpty { info = "There were no clicks to zoom in on." }
    }

    func addZoom() {
        var id: UUID?
        edit { id = $0.addZoom(at: self.time) }
        if let id { select(.zoom(id)) }
    }

    /// Points a zoom at the spot clicked in the preview. `shown` is where in the preview (0...1) the click
    /// landed; while a zoom is showing the preview is already magnified, so that is first mapped back
    /// to the full picture, and then to the recorded window inside it.
    func aimZoom(_ id: UUID, atShown shown: CGPoint) {
        let canvas = videoSize
        let content = CanvasLayout.contentRect(canvas: canvas, source: canvas, background: project.background)
        let state = ZoomCamera.state(at: time, zooms: project.zooms)
        let focus = CanvasLayout.canvasPoint(forSource: state.focusX, state.focusY, content: content, canvas: canvas)
        let crop = ZoomCamera.crop(zoom: state.zoom, focusX: focus.x, focusY: focus.y)
        let inCanvas = CGPoint(x: crop.minX + shown.x * crop.width, y: crop.minY + shown.y * crop.height)
        let point = CanvasLayout.sourcePoint(forCanvas: inCanvas.x, inCanvas.y, content: content, canvas: canvas)
        edit(coalescing: "aim-\(id)") { $0.updateZoom(id) { $0.x = point.x; $0.y = point.y } }
    }

    // MARK: Captions

    @Published private(set) var captionStatus: String?

    /// Turns captions on or off. The first time, the transcript is made on this Mac if the take has none.
    func setCaptionsOn(_ on: Bool) {
        guard ready else { return }
        guard on else { edit { $0.captions = nil }; return }
        guard captionStatus == nil else { return }
        captionStatus = "Reading the recording…"
        Task {
            defer { captionStatus = nil }
            do {
                let cues = try await Transcripts.ensure(for: take) { [weak self] text in self?.captionStatus = text }
                if cues.isEmpty { message = "No speech was found to caption."; return }
                edit { $0.captions = StudioCaptions(cues: cues) }
                library.refresh()
            } catch { message = "Could not make captions: \(error.localizedDescription)" }
        }
    }

    func setCaptionStyle(_ style: CaptionStyle) { edit { $0.captions?.style = style } }
    func setCaptionPosition(_ position: CaptionPosition) { edit { $0.captions?.position = position } }

    // MARK: Editing

    /// Applies one undoable edit. Edits with the same `coalescing` key made close together (typing,
    /// dragging a slider) become a single undo step.
    func edit(coalescing key: String? = nil, _ change: (inout StudioProject) throws -> Void) {
        var next = project
        do { try change(&next) } catch {
            message = error.localizedDescription
            return
        }
        guard next != project else { return }
        let merges = key != nil && key == lastCoalesceKey && Date().timeIntervalSince(lastCoalesceTime) < 1.5
        if !merges { history.record(project) }
        lastCoalesceKey = key
        lastCoalesceTime = Date()
        apply(next)
    }

    /// Dragging: one undo step for the whole drag, with live updates in between.
    func beginGesture() { gestureBase = project }
    /// For drags that report many changes: only the first one starts the undo step.
    func beginGestureIfNeeded() { if gestureBase == nil { gestureBase = project } }

    func live(_ change: (inout StudioProject) -> Void) {
        var next = project
        change(&next)
        if next != project { apply(next, rebuilding: false) }
    }

    func endGesture() {
        if let base = gestureBase, base != project {
            history.record(base)
            lastCoalesceKey = nil
            syncUndoFlags()
            schedulePreview()
        }
        gestureBase = nil
    }

    func undo() {
        guard let previous = history.undo(current: project) else { return }
        lastCoalesceKey = nil
        apply(previous)
    }

    func redo() {
        guard let next = history.redo(current: project) else { return }
        lastCoalesceKey = nil
        apply(next)
    }

    private func apply(_ next: StudioProject, rebuilding: Bool = true) {
        project = next
        syncUndoFlags()
        pruneSelection()
        time = min(time, next.outputDuration)
        if rebuilding { schedulePreview() }
    }

    private func syncUndoFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    private func pruneSelection() {
        switch selection {
        case .text(let id) where project.text(id) == nil: selection = .none
        case .clip(let id) where project.clip(id) == nil: selection = .none
        case .zoom(let id) where project.zoom(id) == nil: selection = .none
        case .range(let range) where range.end > project.outputDuration + 0.01: selection = .none
        default: break
        }
    }

    // MARK: Actions

    func addText() {
        var id: UUID?
        edit { id = $0.addText(at: self.time) }
        if let id { select(.text(id)) }
    }

    func addMusic(from url: URL) {
        Task {
            let file = AVURLAsset(url: url)
            guard let seconds = try? await file.load(.duration).seconds, seconds > 0.1,
                  (try? await file.loadTracks(withMediaType: .audio).first) != nil
            else {
                message = "“\(url.lastPathComponent)” doesn't look like an audio file."
                return
            }
            var id: UUID?
            edit { id = $0.addMusic(url: url, name: url.deletingPathExtension().lastPathComponent, fileDuration: seconds) }
            loadLevels(for: url)
            if let id { selection = .clip(id) }
        }
    }

    func chooseMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a song or sound to play under the video"
        if panel.runModal() == .OK, let url = panel.url { addMusic(from: url) }
    }

    // MARK: Splices

    /// Breaks the video at the playhead. Nothing is removed; the parts either side can be picked, removed, or
    /// have their edges dragged.
    func splice() {
        guard ready else { return }
        var done = false
        edit { done = $0.splice(at: self.time) }
        if done { selection = .none } else { info = "Move the playhead away from the edges (and from other splices) to splice." }
    }

    /// `[`: drop the video before the playhead (within the part it is in).
    func trimBeforePlayhead() {
        guard ready else { return }
        var done = false
        edit { done = $0.trimBefore(self.time) }
        if done { selection = .none; seek(to: time) }
    }

    /// `]`: drop the video after the playhead (within the part it is in).
    func trimAfterPlayhead() {
        guard ready else { return }
        var done = false
        edit { done = $0.trimAfter(self.time) }
        if done { selection = .none; seek(to: time) }
    }

    /// Picks the whole part under a moment of the edited video.
    func selectPart(atOutput output: Double) {
        // With no splices the "part" would be the whole video, which is not something to pick.
        guard project.cuts.segments.count > 1, let index = project.cuts.partIndex(atOutput: output) else {
            if case .range = selection { selection = .none }
            return
        }
        selection = .range(project.cuts.partSpans[index])
    }

    /// Joins two parts that were only spliced.
    func removeSplice(afterPart index: Int) {
        edit { project in
            guard project.cuts.removeSplice(afterPart: index) else { return }
        }
        selection = .none
    }

    /// Something on the Video track that can be dragged: a splice, or an edge of a part.
    enum CutHandle: Equatable {
        case splice(afterPart: Int)
        case edge(part: Int, edge: CutEdge)
    }

    /// Follows a drag of a handle. `base` is the project when the drag began and `seconds` how far the
    /// pointer has moved along the edited timeline, so the result always comes from the start of the drag.
    func drag(_ handle: CutHandle, from base: StudioProject, by seconds: Double) {
        beginGestureIfNeeded()
        let segments = base.cuts.segments
        live { project in
            project = base
            switch handle {
            case .splice(let index):
                guard segments.indices.contains(index) else { return }
                project.cuts.slideSplice(afterPart: index, toSource: segments[index].end + seconds)
            case .edge(let part, let edge):
                guard segments.indices.contains(part) else { return }
                let origin = edge == .start ? segments[part].start : segments[part].end
                project.moveEdge(ofPart: part, edge: edge, toSource: origin + seconds)
            }
        }
        selection = .none
    }

    func removeSection(_ range: TimeSpan) {
        edit { try $0.remove(range) }
        selection = .none
    }

    func keepOnly(_ range: TimeSpan) {
        edit { try $0.keepOnly(range) }
        selection = .none
    }

    func deleteSelection() {
        switch selection {
        case .text(let id): edit { $0.removeText(id) }
        case .zoom(let id): edit { $0.removeZoom(id) }
        case .clip(let id): edit { $0.removeClip(id) }
        case .range(let range): removeSection(range)
        default: return
        }
        selection = .none
    }

    /// Applies cuts suggested from the *original* recording by mapping them onto the edited timeline.
    func applySourceCuts(_ spans: [TimeSpan]) {
        edit { project in
            let outputs = spans.flatMap { project.cuts.outputSpans(forSource: $0) }
            for span in outputs.sorted(by: { $0.start > $1.start }) { try project.remove(span) }
        }
    }

    // MARK: Tighten

    /// Pauses and restarts proposed for this take. They sit on the Video track until you cut or dismiss them. Finding
    /// them cuts nothing.
    @Published private(set) var tighten: [EditSuggestion] = []
    @Published private(set) var tightenStatus: String?
    @Published private(set) var tightenNotes: [String] = []
    @Published private(set) var tightenSearched = false

    /// The proposals still in the edit: one that has been cut out is gone from the timeline, and comes back if undone.
    var pendingTighten: [EditSuggestion] { tighten.filter { !tightenSpans(for: $0).isEmpty } }

    /// Where a proposal sits on the edited timeline (it may be split if part of it was already cut).
    func tightenSpans(for suggestion: EditSuggestion) -> [TimeSpan] { project.cuts.outputSpans(forSource: suggestion.span) }

    /// Looks for pauses at least `pauseLength` seconds long and for restarts. Calls `done` with how many it found.
    func findTighten(pauseLength: Double, done: @escaping (Int) -> Void = { _ in }) {
        guard tightenStatus == nil else { return }
        tightenStatus = "Starting…"
        tightenNotes = []
        Task {
            let result = await EditAnalysis.run(for: take, pauseLength: pauseLength) { [weak self] in self?.tightenStatus = $0 }
            tighten = result.suggestions
            tightenNotes = result.notes
            tightenSearched = true
            tightenStatus = nil
            done(pendingTighten.count)
        }
    }

    /// Puts proposals on the timeline without analysing anything (for the --studio-snapshot check).
    func showTighten(_ suggestions: [EditSuggestion]) { tighten = suggestions; tightenSearched = true }

    func cutTighten(_ suggestions: [EditSuggestion]) { applySourceCuts(suggestions.map(\.span)) }
    func dismissTighten(_ suggestion: EditSuggestion) { tighten.removeAll { $0.id == suggestion.id } }
    func clearTighten() { tighten = []; tightenNotes = []; tightenSearched = false }

    /// Plays the edit from a moment of the *original* recording (or the next kept moment after it).
    func playSource(_ source: Double) {
        let spans = project.cuts.outputSpans(forSource: TimeSpan(start: source, end: source + 1_000_000))
        play(from: spans.first?.start ?? 0)
    }

    func select(_ new: Selection) {
        selection = new
        // Make what you just picked visible in the preview.
        switch new {
        case .text(let id): if let text = project.text(id) { seek(to: text.start + 0.05) }
        case .zoom(let id): if let zoom = project.zoom(id) { seek(to: zoom.start + (zoom.length / 2)) }
        case .clip(let id): if let clip = project.clip(id), time < clip.start || time > clip.start + clip.length { seek(to: clip.start) }
        default: break
        }
    }

    // MARK: Playback (always the edited result)

    func seek(to seconds: Double) {
        let target = min(max(0, seconds), max(0, project.outputDuration - 0.02))
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if time >= project.outputDuration - 0.05 { seek(to: 0) }
            player.play()
        }
    }

    func play(from seconds: Double) {
        seek(to: seconds)
        player.play()
    }

    private func schedulePreview() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await rebuildPreview()
        }
    }

    private var recordingVoice: Bool { voice != .idle }

    /// Rebuilds what plays so the preview always matches what will be saved (minus the text, which the
    /// preview draws on top). The picture and sound resume where they were.
    private func rebuildPreview() async {
        let wasPlaying = isPlaying
        let resumeAt = time
        guard let output = try? await StudioComposer.build(
            asset: asset, project: project, burnText: false, muteOriginal: recordingVoice)
        else { return }
        let item = AVPlayerItem(asset: output.composition)
        item.audioMix = output.audioMix
        item.videoComposition = output.videoComposition  // the backdrop and zoom, when there are any
        player.replaceCurrentItem(with: item)
        await player.seek(to: CMTime(seconds: min(resumeAt, project.outputDuration), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player.play() }
    }

    // MARK: Voiceover

    /// Counts down, then records the microphone while the video plays with its own sound muted.
    func startVoiceover(fromPlayhead: Bool, replaceOriginal: Bool) {
        guard voice == .idle, ready else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: beginCountdown(fromPlayhead: fromPlayhead, replaceOriginal: replaceOriginal)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted { self.beginCountdown(fromPlayhead: fromPlayhead, replaceOriginal: replaceOriginal) }
                    else { self.message = "Hot Take needs microphone access to record a voiceover. Turn it on in System Settings → Privacy & Security → Microphone." }
                }
            }
        default:
            message = "Hot Take needs microphone access to record a voiceover. Turn it on in System Settings → Privacy & Security → Microphone."
        }
    }

    private func beginCountdown(fromPlayhead: Bool, replaceOriginal: Bool) {
        voiceStart = fromPlayhead ? time : 0
        voiceReplacesOriginal = replaceOriginal
        player.pause()
        seek(to: voiceStart)
        voice = .countdown(3)
        voiceTask = Task {
            for remaining in stride(from: 3, through: 1, by: -1) {
                voice = .countdown(remaining)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            await beginRecording()
        }
    }

    private func beginRecording() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("relaytake-voiceover-\(UUID().uuidString).m4a")
        let choice = Microphone.chosen(id: UserDefaults.standard.string(forKey: "voiceoverMicrophone") ?? "")
        if choice.fellBack { message = "The microphone you chose isn't connected, so the default one is being used." }
        let recorder = MicrophoneRecorder(url: url)
        do {
            try recorder.start(device: choice.device)
        } catch {
            voice = .idle
            message = "Could not start recording: \(error.localizedDescription)"
            return
        }
        self.recorder = recorder
        voice = .recording
        await rebuildPreview()  // plays without the original sound so the microphone doesn't hear it
        seek(to: voiceStart)
        player.play()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                self.inputLevel = recorder.level
            }
        }
    }

    /// Stops recording and puts the take on the Voiceover track at the moment it began.
    func finishVoiceover() {
        guard voice == .recording, let recorder else { return }
        self.recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        inputLevel = 0
        player.pause()
        let start = voiceStart
        let replace = voiceReplacesOriginal
        voice = .idle
        Task {
            guard let url = await recorder.stop() else {
                message = "Nothing was recorded. Check the microphone you chose."
                await rebuildPreview()
                return
            }
            let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard seconds > 0.3 else {
                message = "That recording was too short to keep."
                await rebuildPreview()
                return
            }
            var id: UUID?
            edit {
                id = $0.addVoiceover(url: url, name: "Voiceover", fileDuration: seconds, start: start)
                if replace { $0.originalVolume = 0 }
            }
            loadLevels(for: url)
            if let id { selection = .clip(id) }
            await rebuildPreview()
        }
    }

    func cancelVoiceover() {
        voiceTask?.cancel()
        recorder?.discard()
        recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        inputLevel = 0
        player.pause()
        voice = .idle
        Task { await rebuildPreview() }
    }

    // MARK: Saving

    /// A copy needs saving when something was edited, or when it is to be made smaller or silent.
    func canSave(_ options: StudioSaveOptions) -> Bool {
        ready && voice == .idle && (project.isEdited || options.quality != nil || !options.includeAudio)
    }

    /// Renders the edit to a new recording beside the original (an MP4 in your library). A copy that has
    /// edits gets fresh captions and a summary; a copy that is only smaller keeps the original's.
    func save(options: StudioSaveOptions, done: @escaping () -> Void) {
        guard saveProgress == nil, canSave(options) else { return }
        player.pause()
        saveProgress = 0
        saveStatus = "Saving…"
        let name = TakeLibrary.uniqueCopyName(basedOn: take.files.baseName, in: take.files.directory)
        let copy = TakeFiles(directory: take.files.directory, baseName: name)
        let snapshot = project
        let original = take
        saveTask = Task {
            defer { saveProgress = nil; saveTask = nil }
            do {
                try await StudioSaver.render(
                    asset: asset, project: snapshot, to: copy.video, format: .mp4, options: options
                ) { self.saveProgress = $0 }
                try Task.checkCancellation()
                var notes: [String] = []
                if snapshot.isEdited {
                    let defaults = UserDefaults.standard
                    let wants = { (key: String) in defaults.object(forKey: key) as? Bool ?? true }
                    notes = await Pipeline.process(
                        take: copy, created: Date(),
                        options: .init(captions: wants(Pref.captions), summary: wants(Pref.summary))
                    ) { self.saveStatus = $0 }
                } else {
                    // Only the file changed, not what is said: carry over the captions and notes.
                    var metadata = TakeLibrary.metadata(for: original.files)
                        ?? TakeMetadata(title: original.title, summary: original.summary, created: Date())
                    metadata.created = Date()
                    metadata.durationSeconds = snapshot.outputDuration
                    do {
                        try metadata.encoded().write(to: copy.metadata, options: .atomic)
                        if FileManager.default.fileExists(atPath: original.files.captions.path) {
                            try FileManager.default.copyItem(at: original.files.captions, to: copy.captions)
                        }
                    } catch { notes.append("The video was saved, but its notes could not be copied.") }
                }
                // Remember which recording this was made from, so the library nests it under its original.
                try? TakeLibrary.link(copy: copy, to: original.files, created: Date())
                library.expandVersions(of: original)
                library.select(files: copy)
                if !notes.isEmpty { message = notes.joined(separator: " ") }
                done()
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: copy.video)
                saveStatus = "Canceled. No copy was kept."
            } catch {
                try? FileManager.default.removeItem(at: copy.video)
                message = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    /// Renders the edit to a file you choose, as MP4, MOV or WebM. Your library is not changed.
    func export(format: VideoExportFormat, options: StudioSaveOptions) {
        guard saveProgress == nil, ready, voice == .idle else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .movie]
        panel.nameFieldStringValue = take.files.baseName + "." + format.rawValue
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.resolvingSymlinksInPath() != take.files.video.standardizedFileURL.resolvingSymlinksInPath() else {
            message = "Choose a different name to keep your original."
            return
        }
        player.pause()
        saveProgress = 0
        saveStatus = "Exporting \(format.rawValue.uppercased())…"
        let snapshot = project
        saveTask = Task {
            defer { saveProgress = nil; saveTask = nil }
            do {
                try await StudioSaver.render(asset: asset, project: snapshot, to: url, format: format, options: options) {
                    self.saveProgress = $0
                }
                info = "Exported “\(url.lastPathComponent)”."
            } catch is CancellationError {
                info = "Export canceled."
            } catch {
                message = "Could not export: \(error.localizedDescription)"
            }
        }
    }

    func cancelSave() { saveTask?.cancel() }

    /// Called when the Studio goes away: stop playing and drop an unfinished recording.
    func shutdown() {
        player.pause()
        if voice != .idle { cancelVoiceover() }
        rebuildTask?.cancel()
    }
}
