import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI

// What a local agent can do once the person has turned on Settings ▸ Recording ▸ "Let local agents control recording":
// start and stop a take of a screen, drop named markers while it drives the demo, then describe an edit as a list that
// lands in the take's Studio draft, and save the result as a new copy. Recording is still owned by the app (RecorderModel),
// never by the process that asked, so an agent that exits cannot lose a take. The control bar stays on screen the whole time.

extension RecorderModel {
    /// An agent's take that is never stopped is stopped and saved after this long.
    nonisolated static let agentTakeLimit: Duration = .seconds(30 * 60)

    private var agentState: String {
        switch phase {
        case .idle: "idle"
        case .recording: paused ? "paused" : "recording"
        case .saving, .processing: "busy"
        }
    }

    func handleAgent(_ request: AgentRequest) async -> AgentResponse {
        guard let command = AgentCommand(rawValue: request.command) else {
            return .failure("Unknown command “\(request.command)”. Commands: \(AgentCommand.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        agentLastSeen = Date()
        switch command {
        case .ping: return AgentResponse(state: agentState)
        case .status: return agentStatus()
        case .start: return await agentStart(display: request.display)
        case .stop: return await agentStop()
        case .pause: return await agentPause()
        case .resume: return await agentResume()
        case .marker: return agentMarker(named: request.name)
        case .markers: return agentMarkerList(take: request.take)
        case .edit: return await agentEdit(request)
        case .render: return await agentRender(request)
        }
    }

    /// Called when the setting is turned off: an agent's take that is still recording is saved, not left running.
    func agentWasTurnedOff() {
        guard agentLimit != nil, isRecording else { return }
        message = "Local agent control was turned off, so the recording was stopped and saved."
        Task { _ = await agentStop() }
    }

    // MARK: Recording

    private func agentStatus() -> AgentResponse {
        AgentResponse(
            state: agentState, take: current?.files.baseName, video: current?.files.video.path,
            seconds: isRecording ? elapsed(at: Date()) : nil, markers: isRecording ? agentMarkers : nil)
    }

    private func agentStart(display: Int?) async -> AgentResponse {
        guard phase == .idle else { return .failure("Hot Take is \(agentState) and cannot start a take now.") }
        let id: CGDirectDisplayID
        if let display {
            guard NSScreen.screens.indices.contains(display - 1), let found = NSScreen.screens[display - 1].displayID else {
                return .failure("There is no display \(display). This Mac has \(NSScreen.screens.count).")
            }
            id = found
        } else if let found = quickDisplay() {
            id = found
        } else {
            return .failure("No display was found to record.")
        }
        begin(.screen(id))
        // The countdown runs first, so wait until the take is really recording (or has failed).
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if isRecording { break }
            if phase == .idle { break }
            try? await Task.sleep(for: .milliseconds(120))
        }
        guard isRecording, let files = current?.files else {
            return .failure(message.isEmpty ? "Recording did not start." : message)
        }
        agentLimit?.cancel()
        agentLimit = Task { [weak self] in
            try? await Task.sleep(for: Self.agentTakeLimit)
            guard !Task.isCancelled, let self, self.isRecording, self.current?.files == files else { return }
            self.message = "An agent's recording ran for 30 minutes without being stopped, so it was stopped and saved."
            _ = await self.agentStop()
        }
        return AgentResponse(state: agentState, take: files.baseName, video: files.video.path)
    }

    private func agentStop() async -> AgentResponse {
        guard isRecording, let files = current?.files else { return .failure("Nothing is being recorded.") }
        agentLimit?.cancel()
        agentLimit = nil
        let length = elapsed(at: Date())
        let markers = agentMarkers.filter { $0.time <= length + 0.5 }
        await stop()
        guard FileManager.default.fileExists(atPath: files.video.path) else {
            return .failure(message.isEmpty ? "The recording was not saved." : message)
        }
        try? AgentMarkerStore.save(markers, for: files)
        lastAgentTake = files
        let seconds = TakeLibrary.metadata(for: files)?.durationSeconds ?? length
        return AgentResponse(
            state: agentState, take: files.baseName, video: files.video.path, seconds: seconds, markers: markers,
            warnings: message.isEmpty ? nil : [message])
    }

    private func agentPause() async -> AgentResponse {
        guard isRecording else { return .failure("Nothing is being recorded.") }
        guard canPause else { return .failure("This take cannot be paused.") }
        if !paused { pause() }
        return AgentResponse(state: agentState, take: current?.files.baseName)
    }

    private func agentResume() async -> AgentResponse {
        guard isRecording else { return .failure("Nothing is being recorded.") }
        guard paused else { return AgentResponse(state: agentState, take: current?.files.baseName) }
        resume()
        let deadline = Date().addingTimeInterval(15)
        while paused, Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        return AgentResponse(state: agentState, take: current?.files.baseName)
    }

    private func agentMarker(named raw: String?) -> AgentResponse {
        guard isRecording else { return .failure("Markers can only be added while recording.") }
        let name = AgentMarkerStore.cleanedName(raw) ?? "Marker \(agentMarkers.count + 1)"
        let marker = AgentMarker(name: name, time: elapsed(at: Date()))
        agentMarkers.append(marker)
        return AgentResponse(state: agentState, take: current?.files.baseName, seconds: marker.time, markers: [marker])
    }

    private func agentMarkerList(take name: String?) -> AgentResponse {
        if name == nil, isRecording { return AgentResponse(state: agentState, take: current?.files.baseName, markers: agentMarkers) }
        guard let files = agentTake(named: name) else { return .failure("No recording found.") }
        return AgentResponse(take: files.baseName, markers: AgentMarkerStore.load(for: files))
    }

    // MARK: Takes

    /// The take a command is about: the one named, else the one an agent recorded last, else the newest in the library.
    private func agentTake(named name: String?) -> TakeFiles? {
        LibraryModel.shared.refresh()
        if let name, !name.isEmpty {
            return LibraryModel.shared.takes.first { $0.files.baseName == name || $0.id == name }?.files
        }
        if let last = lastAgentTake, FileManager.default.fileExists(atPath: last.video.path) { return last }
        return LibraryModel.shared.takes.max { $0.created < $1.created }?.files
    }

    /// What the Studio would open for this take: the screen on its own when a camera was drawn in, else the video.
    private func agentSource(for files: TakeFiles) -> (asset: AVURLAsset, camera: CameraSource?) {
        let fileManager = FileManager.default
        let hasOriginals = fileManager.fileExists(atPath: files.screenOriginal.path)
        let asset = AVURLAsset(url: hasOriginals ? files.screenOriginal : files.video)
        var camera: CameraSource?
        if let metadata = TakeLibrary.metadata(for: files), let offset = metadata.cameraOffset,
           hasOriginals, fileManager.fileExists(atPath: files.cameraOriginal.path) {
            camera = CameraSource(url: files.cameraOriginal, offset: offset, placement: metadata.cameraPlacement)
        }
        return (asset, camera)
    }

    private func agentEditable(_ files: TakeFiles) -> AgentResponse? {
        if current?.files == files, phase != .idle { return .failure("That take is still being recorded.") }
        if StudioModel.isOpen(files) { return .failure("That take is open in the Studio. Close the Studio first so its edits are not overwritten.") }
        return nil
    }

    // MARK: Editing

    private func agentEdit(_ request: AgentRequest) async -> AgentResponse {
        guard let list = request.edit else { return .failure("edit needs an edit list.") }
        guard let files = agentTake(named: request.take) else { return .failure("No recording found.") }
        if let refusal = agentEditable(files) { return refusal }
        let (asset, camera) = agentSource(for: files)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else {
            return .failure("That recording could not be read.")
        }
        let metadata = TakeLibrary.metadata(for: files)
        let markers = AgentMarkerStore.load(for: files)
        let result = AgentEdit.run(
            list, files: files, duration: duration, camera: camera, title: metadata?.title ?? "", markers: markers,
            clicks: metadata?.clicks ?? [])
        switch result {
        case .failure(let failure):
            return AgentResponse(ok: false, error: failure.message, take: files.baseName, warnings: failure.warnings.isEmpty ? nil : failure.warnings)
        case .success(let done):
            LibraryModel.shared.refresh()
            return AgentResponse(
                take: files.baseName, video: files.video.path, seconds: done.project.outputDuration,
                markers: markers.isEmpty ? nil : markers, applied: done.outcome.applied,
                warnings: done.outcome.warnings.isEmpty ? nil : done.outcome.warnings, narration: done.narration?.path)
        }
    }

    private func agentRender(_ request: AgentRequest) async -> AgentResponse {
        guard let files = agentTake(named: request.take) else { return .failure("No recording found.") }
        if let refusal = agentEditable(files) { return refusal }
        let (asset, camera) = agentSource(for: files)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0 else {
            return .failure("That recording could not be read.")
        }
        guard let draft = StudioDraftStore(files: files).load(),
              let project = draft.project(duration: duration, cameraSource: camera), project.isEdited
        else { return .failure("That take has no edits to save yet. Send an edit first.") }

        let markers = AgentMarkerStore.load(for: files)
        let chapters = request.edit?.chapters == false ? [] : ChapterList.remapped(AgentMarkerStore.chapters(from: markers), through: project.cuts)
        let copy = TakeFiles(directory: files.directory, baseName: TakeLibrary.uniqueCopyName(basedOn: files.baseName, in: files.directory))
        let defaults = UserDefaults.standard
        let wants = { (key: String) in defaults.object(forKey: key) as? Bool ?? true }
        do {
            try await StudioSaver.render(
                asset: asset, project: project, to: copy.video, format: .mp4, options: .stored, chapters: chapters
            ) { _ in }
            var notes = await Pipeline.process(
                take: copy, created: Date(), options: .init(captions: wants(Pref.captions), summary: wants(Pref.summary))
            ) { _ in }
            if !chapters.isEmpty {
                try? TakeLibrary.saveChapters(chapters, to: copy, created: Date(), duration: project.outputDuration, chaptersEnabled: true)
            }
            try? TakeLibrary.link(copy: copy, to: files, created: Date())
            StudioDraftStore(files: files).discard()
            LibraryModel.shared.refresh()
            LibraryModel.shared.select(files: copy)
            notes = notes.filter { !$0.isEmpty }
            return AgentResponse(
                take: copy.baseName, seconds: project.outputDuration, warnings: notes.isEmpty ? nil : notes, output: copy.video.path)
        } catch {
            try? FileManager.default.removeItem(at: copy.video)
            return .failure("Could not save the edited copy: \(error.localizedDescription)")
        }
    }
}

/// Settings ▸ Recording: the switch that lets agents on this Mac in. Off unless the person turns it on.
struct AgentControlSection: View {
    @AppStorage(Pref.agentControl) private var enabled = false

    var body: some View {
        Section {
            Toggle("Let local agents control recording", isOn: $enabled)
                .help("Lets programs you run on this Mac, such as Claude Code or Codex, start and stop a screen recording, mark moments in it and edit it, using the hottake command. The recording bar stays on screen while they record. Nothing leaves this Mac.")
                .onChange(of: enabled) { _, _ in AgentServer.shared.refresh() }
            LabeledContent("Setup") {
                Button("Set Up an Agent…") { RecorderModel.current?.showingAgentSetup = true; RecorderModel.current?.libraryRequest += 1 }
                    .help("Shows how to connect Claude Code, Codex or another agent, with text to copy.")
            }
            if enabled {
                Text("Only your own account can connect. An agent’s recording stops by itself after 30 minutes, and turning this off stops one that is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Agents")
        }
    }
}
