import AVFoundation
import AppKit
import RelaytakeCore
import SwiftUI
import UniformTypeIdentifiers

private enum Metrics {
    static let label: CGFloat = 78
    static let ruler: CGFloat = 22
    static let row: CGFloat = 34
    static let gap: CGFloat = 4
    static let pad: CGFloat = 10
    static let rows = 6
    static var height: CGFloat { ruler + CGFloat(rows) * (row + gap) + 12 }
}

/// Five tracks, always fitted to the window's width so there is nothing to scroll sideways:
/// the picture (with cuts), text, the recording's own sound, music, and voiceover.
struct StudioTimeline: View {
    @ObservedObject var model: StudioModel

    var body: some View {
        GeometryReader { geometry in
            let width = max(60, geometry.size.width - Metrics.label - Metrics.pad * 2 - 8)
            let total = max(model.project.outputDuration, 0.1)
            let pps = width / total
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: Metrics.gap) {
                    Color.clear.frame(height: Metrics.ruler)
                    TrackLabel(symbol: "film", title: "Video")
                    TrackLabel(symbol: "textformat", title: "Text")
                    TrackLabel(symbol: "plus.magnifyingglass", title: "Zoom")
                    TrackLabel(symbol: "waveform", title: "Audio")
                    TrackLabel(symbol: "music.note", title: "Music")
                    TrackLabel(symbol: "mic", title: "Voiceover")
                }
                .frame(width: Metrics.label, alignment: .leading)

                ZStack(alignment: .topLeading) {
                    VStack(spacing: Metrics.gap) {
                        Ruler(model: model, width: width, total: total)
                        VideoTrack(model: model, width: width, total: total)
                            .overlay(alignment: .topLeading) { TightenMarks(model: model, pps: pps) }
                        TextTrack(model: model, pps: pps)
                        ZoomTrack(model: model, pps: pps)
                        OriginalTrack(model: model, pps: pps, total: total)
                        AudioClipTrack(model: model, kind: .music, pps: pps,
                                       hint: "Drop an audio file here, or choose Add Music")
                        AudioClipTrack(model: model, kind: .voiceover, pps: pps,
                                       hint: "Choose Voiceover to talk over the video")
                    }
                    Playhead(clock: model.clock, pps: pps, width: width)
                }
                .frame(width: width)
            }
            .padding(.horizontal, Metrics.pad)
            .padding(.top, 4)
        }
        .frame(height: Metrics.height)
        // Drop a song straight onto the timeline.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { isAudio($0) }) else { return false }
            model.addMusic(from: url)
            return true
        }
    }

    private func isAudio(_ url: URL) -> Bool {
        (UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio)) ?? false
    }
}

private struct TrackLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: Metrics.row, alignment: .center)
    }
}

private struct Playhead: View {
    @ObservedObject var clock: StudioClock
    let pps: CGFloat
    let width: CGFloat

    var body: some View {
        let x = min(width, max(0, clock.time * pps))
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundStyle(.red)
            Rectangle().fill(.red).frame(width: 1.5)
        }
        .frame(width: 12, height: Metrics.height - 8)
        .offset(x: x - 6)
        .allowsHitTesting(false)
    }
}

// MARK: Ruler

private struct Ruler: View {
    @ObservedObject var model: StudioModel
    let width: CGFloat
    let total: Double

    var body: some View {
        let pps = width / total
        let step = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600].first { $0 * pps >= 56 } ?? 600
        Canvas { context, size in
            var t = 0.0
            while t <= total + 0.001 {
                let x = t * pps
                context.fill(Path(CGRect(x: x, y: size.height - 7, width: 1, height: 7)), with: .color(.secondary))
                context.draw(Text(shortTime(t)).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: 7), anchor: .leading)
                t += step
            }
        }
        .frame(height: Metrics.ruler)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in model.seek(to: Double(value.location.x) / Double(pps)) })
        .pointerStyle(.columnResize)
    }

    private func shortTime(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return seconds < 60 && step < 1 ? String(format: "%.1fs", seconds) : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private var step: Double { 1 }
}

// MARK: Video track

private struct ThumbKey: Equatable {
    var count: Int
    var spans: [Double]
}

private struct VideoTrack: View {
    @ObservedObject var model: StudioModel
    let width: CGFloat
    let total: Double
    @State private var thumbnails: [NSImage] = []
    /// What the current drag is doing, decided on its first movement.
    @State private var dragging: Drag?
    @State private var hoverX: CGFloat?
    @State private var showingResizeCursor = false

    private enum Drag {
        case handle(StudioModel.CutHandle, base: StudioProject, pps: CGFloat)
        case choose
    }

    /// How close (points) the pointer has to be to a splice or an edge to grab it.
    private static let grip: CGFloat = 7
    /// The visible space between two parts.
    private static let gap: CGFloat = 8

    var body: some View {
        let pps = width / total
        let count = max(1, Int(width / (Metrics.row * 16 / 9)))
        let parts = model.project.cuts.partSpans
        // Each part is its own rounded block with a little space between blocks. The space is cut out of the
        // picture, not added to it, so times still line up with the ruler.
        let frames: [(x: CGFloat, width: CGFloat)] = parts.enumerated().map { index, part in
            let left: CGFloat = index == 0 ? 0 : Self.gap / 2
            let right: CGFloat = index == parts.count - 1 ? 0 : Self.gap / 2
            return (part.start * pps + left, max(2, (part.end - part.start) * pps - left - right))
        }
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.blue.opacity(0.25))
                // Frames along the edited video.
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: width / CGFloat(max(thumbnails.count, 1)), height: Metrics.row).clipped()
                    }
                }
            }
            .frame(width: width, height: Metrics.row)
            .mask(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        RoundedRectangle(cornerRadius: 6).frame(width: frame.width, height: Metrics.row).offset(x: frame.x)
                    }
                }
                .frame(width: width, height: Metrics.row, alignment: .topLeading)
            }

            // The chosen part or section.
            if case .range(let range) = model.selection {
                let partFrame = parts.firstIndex { abs($0.start - range.start) < 0.01 && abs($0.end - range.end) < 0.01 }.map { frames[$0] }
                let x = partFrame?.x ?? range.start * pps
                let w = partFrame?.width ?? max(2, range.length * pps)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.3))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow, lineWidth: 2))
                    .frame(width: w, height: Metrics.row)
                    .offset(x: x)
                // Grips on its ends: drag to trim in or out.
                ForEach([x, x + w], id: \.self) { edge in
                    RoundedRectangle(cornerRadius: 2).fill(Color.yellow)
                        .frame(width: 5, height: Metrics.row - 10)
                        .offset(x: edge - 2.5, y: 5)
                }
            }

            // The scissors sit in each gap: dark for a plain splice, orange where something was removed.
            ForEach(Array(parts.dropLast().enumerated()), id: \.offset) { index, part in
                let spliced = model.project.cuts.isSplice(afterPart: index)
                Image(systemName: "scissors").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(spliced ? Color(white: 0.2) : Color.orange))
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: part.end * pps - 8, y: -5)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: Metrics.row)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hoverX = point.x
                let overHandle = handle(at: point.x, pps: pps) != nil
                if overHandle != showingResizeCursor {
                    showingResizeCursor = overHandle
                    if overHandle { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
            case .ended:
                hoverX = nil
                if showingResizeCursor { NSCursor.pop(); showingResizeCursor = false }
            }
        }
        // Click a part to choose it and move the playhead; drag a splice or an edge to move it; drag across
        // the track to choose any stretch.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragging == nil {
                        if let handle = handle(at: value.startLocation.x, pps: pps) {
                            dragging = .handle(handle, base: model.project, pps: pps)
                        } else {
                            dragging = .choose
                        }
                    }
                    switch dragging {
                    case .handle(let handle, let base, let basePPS):
                        guard abs(value.translation.width) > 1 else { return }
                        model.drag(handle, from: base, by: Double(value.translation.width / basePPS))
                    case .choose:
                        guard abs(value.translation.width) > 3 else { return }
                        let a = clamp(value.startLocation.x / pps), b = clamp(value.location.x / pps)
                        model.selection = .range(TimeSpan(start: min(a, b), end: max(a, b)))
                    case nil: break
                    }
                }
                .onEnded { value in
                    defer { dragging = nil }
                    switch dragging {
                    case .handle:
                        model.endGesture()
                    case .choose, nil:
                        if abs(value.translation.width) <= 3 {
                            let time = clamp(value.location.x / pps)
                            model.seek(to: time)
                            model.selectPart(atOutput: time)
                        } else if case .range(let range) = model.selection, range.length < 0.15 {
                            model.selection = .none
                        }
                    }
                }
        )
        .contextMenu {
            // Right-click works on whatever is under the pointer.
            let time = clamp((hoverX ?? 0) / pps)
            Button("Splice Here", systemImage: "scissors") { model.seek(to: time); model.splice() }
            if let index = model.project.cuts.partIndex(atOutput: time) {
                Button("Remove This Part", systemImage: "trash") {
                    model.removeSection(model.project.cuts.partSpans[index])
                }
                if index > 0, let hover = hoverX, abs(parts[index].start * pps - hover) <= 12,
                   model.project.cuts.isSplice(afterPart: index - 1) {
                    Button("Remove Splice", systemImage: "arrow.left.and.right.square") { model.removeSplice(afterPart: index - 1) }
                }
                if index + 1 < parts.count, let hover = hoverX, abs(parts[index].end * pps - hover) <= 12,
                   model.project.cuts.isSplice(afterPart: index) {
                    Button("Remove Splice", systemImage: "arrow.left.and.right.square") { model.removeSplice(afterPart: index) }
                }
            }
        }
        .task(id: ThumbKey(count: count, spans: model.project.cuts.segments.flatMap { [$0.start, $0.end] })) {
            thumbnails = await loadThumbnails(count: count)
        }
    }

    /// The splice or edge near a horizontal position, if any.
    private func handle(at x: CGFloat, pps: CGFloat) -> StudioModel.CutHandle? {
        let cuts = model.project.cuts
        let parts = cuts.partSpans
        guard !parts.isEmpty else { return nil }
        // Between parts: a splice slides; at a gap, the left half pulls the part before it and the right half
        // the part after it.
        for index in parts.indices.dropLast() {
            let position = parts[index].end * pps
            guard abs(x - position) <= Self.grip else { continue }
            if cuts.isSplice(afterPart: index) { return .splice(afterPart: index) }
            return x < position ? .edge(part: index, edge: .end) : .edge(part: index + 1, edge: .start)
        }
        // The two ends of the video.
        if x <= Self.grip { return .edge(part: 0, edge: .start) }
        if x >= parts[parts.count - 1].end * pps - Self.grip { return .edge(part: parts.count - 1, edge: .end) }
        return nil
    }

    private func clamp(_ seconds: Double) -> Double { min(max(0, seconds), total) }

    private func loadThumbnails(count: Int) async -> [NSImage] {
        let generator = AVAssetImageGenerator(asset: model.sourceAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 135)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let cuts = model.project.cuts
        var times: [CMTime] = []
        for index in 0..<count {
            let output = (Double(index) + 0.5) / Double(count) * total
            times.append(CMTime(seconds: cuts.sourceTime(forOutput: output) ?? 0, preferredTimescale: 600))
        }
        var images: [Int: NSImage] = [:]
        for await result in generator.images(for: times) {
            if case .success(let requested, let image, _) = result,
               let index = times.firstIndex(where: { CMTimeCompare($0, requested) == 0 }) {
                images[index] = NSImage(cgImage: image, size: .zero)
            }
        }
        return (0..<count).compactMap { images[$0] }
    }
}

// MARK: Text track

private struct TextTrack: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat

    var body: some View {
        let lanes = model.project.textLanes()
        let laneHeight = (Metrics.row - 3) / 2
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
            if model.project.texts.isEmpty {
                Text("Choose Add Text to put words on the video").font(.caption).foregroundStyle(.tertiary).padding(.leading, 8)
                    .frame(height: Metrics.row)
            }
            ForEach(model.project.texts) { text in
                let lane = min(lanes[text.id] ?? 0, 1)
                TimelineBlock(
                    start: text.start, end: text.end, pps: pps, height: laneHeight, yOffset: 1.5 + CGFloat(lane) * (laneHeight + 0),
                    selected: model.selection == .text(text.id), tint: .orange,
                    onSelect: { model.select(.text(text.id)) },
                    onBegin: { model.beginGestureIfNeeded() },
                    onMove: { newStart in model.live { $0.moveText(text.id, to: newStart) } },
                    onResize: { start, end in model.live { $0.updateText(text.id) { $0.start = start; $0.end = end } } },
                    onEnd: { model.endGesture() }
                ) {
                    Text(text.text).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 6)
                }
            }
        }
        .frame(height: Metrics.row)
    }
}

/// The bracket shown on the Video track for a start or end mark.
private struct MarkFlag: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
            .frame(width: 14, height: Metrics.row)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 3))
            .allowsHitTesting(false)
    }
}

// MARK: Zoom track

private struct ZoomTrack: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
            if model.project.zooms.isEmpty {
                Text(model.clicks.isEmpty ? "Choose Auto Zoom to add a zoom" : "Choose Auto Zoom to zoom in on your clicks")
                    .font(.caption).foregroundStyle(.tertiary).padding(.leading, 8).frame(height: Metrics.row)
            }
            ForEach(model.project.zooms) { zoom in
                TimelineBlock(
                    start: zoom.start, end: zoom.end, pps: pps, height: Metrics.row - 4, yOffset: 2,
                    selected: model.selection == .zoom(zoom.id), tint: .teal,
                    onSelect: { model.select(.zoom(zoom.id)) },
                    onBegin: { model.beginGestureIfNeeded() },
                    onMove: { newStart in model.live { $0.moveZoom(zoom.id, to: newStart) } },
                    onResize: { start, end in model.live { $0.updateZoom(zoom.id) { $0.start = start; $0.end = end } } },
                    onEnd: { model.endGesture() }
                ) {
                    Text(String(format: "%.1f×", zoom.scale)).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 6)
                }
            }
        }
        .frame(height: Metrics.row)
    }
}

// MARK: Original audio

private struct OriginalTrack: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat
    let total: Double

    var body: some View {
        let selected = model.selection == .original
        let volume = model.project.originalVolume
        let levels = model.levels[model.take.files.video]
        let color = Color.green.opacity(volume == 0 ? 0.25 : 0.9)
        let linked = model.project.originalAudioFollowsVideo
        let parts = model.project.originalAudioParts
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(linked ? Color.green.opacity(selected ? 0.4 : 0.22) : Color.secondary.opacity(selected ? 0.25 : 0.12))
            if linked {
                Waveform(levels: levels, duration: total, color: color) { t in model.project.cuts.sourceTime(forOutput: t) }
                    .padding(.vertical, 3)
            } else {
                ForEach(parts) { part in
                    let partSelected = model.selection == .audioPart(part.id)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(Color.green.opacity(partSelected ? 0.4 : 0.22))
                        Waveform(levels: levels, duration: part.length, color: color) { t in part.source.start + t }
                            .padding(.vertical, 3)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: partSelected ? 2 : 0))
                    .frame(width: max(2, part.length * pps), height: Metrics.row - 4)
                    .offset(x: part.start * pps, y: 2)
                    .onTapGesture { model.select(.audioPart(part.id)) }
                }
            }
            // The scissors show each break: dark where parts touch, orange where sound was taken out.
            ForEach(Array(zip(parts, parts.dropFirst()).enumerated()), id: \.offset) { _, pair in
                let touching = abs(pair.0.end - pair.1.start) < 0.001
                Image(systemName: "scissors").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(touching ? Color(white: 0.2) : Color.orange))
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: pair.0.end * pps - 8, y: -5)
                    .allowsHitTesting(false)
            }
            Text(volume == 0 ? "Original audio · muted" : "Original audio" + (volume == 1 ? "" : " · \(Int(volume * 100))%"))
                .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                .background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white).padding(.leading, 4)
                .frame(height: Metrics.row, alignment: .leading)
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: selected ? 2 : 0))
        .frame(height: Metrics.row)
        .contentShape(Rectangle())
        .onTapGesture { model.selection = .original }
    }
}

// MARK: Music and voiceover

private struct AudioClipTrack: View {
    @ObservedObject var model: StudioModel
    let kind: AudioClip.Kind
    let pps: CGFloat
    let hint: String

    var body: some View {
        let clips = model.project.clips.filter { $0.kind == kind }
        let total = model.project.outputDuration
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12))
            if clips.isEmpty {
                Text(hint).font(.caption).foregroundStyle(.tertiary).padding(.leading, 8).frame(height: Metrics.row)
            }
            ForEach(clips) { clip in
                let playing = clip.effectiveLength(outputDuration: total)
                TimelineBlock(
                    start: clip.start, end: clip.start + playing, pps: pps, height: Metrics.row - 4, yOffset: 2,
                    selected: model.selection == .clip(clip.id), tint: kind == .music ? .purple : .pink, canResizeStart: false,
                    onSelect: { model.select(.clip(clip.id)) },
                    onBegin: { model.beginGestureIfNeeded() },
                    onMove: { newStart in model.live { $0.updateClip(clip.id) { $0.start = newStart } } },
                    onResize: { _, end in
                        model.live { $0.updateClip(clip.id) { $0.length = max(0.1, end - $0.start); $0.fitsVideo = false } }
                    },
                    onEnd: { model.endGesture() }
                ) {
                    ZStack(alignment: .leading) {
                        Waveform(levels: model.levels[clip.url], duration: playing, color: .white.opacity(0.85)) { t in
                            let position = clip.sourceStart + t
                            return clip.loops ? position.truncatingRemainder(dividingBy: max(clip.sourceDuration, 0.1)) : (position < clip.sourceDuration ? position : nil)
                        }
                        Text(clip.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 5).background(.black.opacity(0.4), in: Capsule()).foregroundStyle(.white)
                            .padding(.leading, 4)
                    }
                }
            }
        }
        .frame(height: Metrics.row)
    }
}

// MARK: Shared pieces

/// A clip on a track. Drag the body to move it, the edges to resize it.
private struct TimelineBlock<Content: View>: View {
    let start: Double
    let end: Double
    let pps: CGFloat
    let height: CGFloat
    let yOffset: CGFloat
    let selected: Bool
    let tint: Color
    var canResizeStart = true
    let onSelect: () -> Void
    let onBegin: () -> Void
    let onMove: (Double) -> Void
    let onResize: (Double, Double) -> Void
    let onEnd: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var origin: (start: Double, end: Double)?

    var body: some View {
        let width = max(8, (end - start) * pps)
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(tint.opacity(selected ? 0.95 : 0.75))
            content().clipShape(RoundedRectangle(cornerRadius: 5))
            RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.white : tint.opacity(0.4), lineWidth: selected ? 2 : 1)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .leading) { if canResizeStart { handle(.start) } }
        .overlay(alignment: .trailing) { handle(.end) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    begin()
                    let base = origin!
                    onMove(base.start + Double(value.translation.width / pps))
                }
                .onEnded { _ in finish() }
        )
        .offset(x: start * pps, y: yOffset)
    }

    private enum Edge { case start, end }

    private func handle(_ edge: Edge) -> some View {
        Rectangle().fill(Color.clear).frame(width: 9)
            .contentShape(Rectangle())
            .overlay(Capsule().fill(.white.opacity(selected ? 0.9 : 0.0)).frame(width: 3, height: height * 0.5))
            .pointerStyle(.columnResize)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        begin()
                        let base = origin!
                        let delta = Double(value.translation.width / pps)
                        switch edge {
                        case .start: onResize(min(base.start + delta, base.end - 0.3), base.end)
                        case .end: onResize(base.start, max(base.end + delta, base.start + 0.3))
                        }
                    }
                    .onEnded { _ in finish() }
            )
    }

    private func begin() {
        if origin == nil {
            origin = (start, end)
            onSelect()
            onBegin()
        }
    }

    private func finish() {
        origin = nil
        onEnd()
    }
}

/// Loudness bars from a file's measured levels (dB per 0.1 s). `sourceTime` maps a moment in this
/// clip (seconds from its left edge) to a moment in the file.
private struct Waveform: View {
    let levels: [Double]?
    let duration: Double
    let color: Color
    let sourceTime: (Double) -> Double?

    var body: some View {
        Canvas { context, size in
            guard duration > 0, size.width > 0 else { return }
            guard let levels, !levels.isEmpty else {
                context.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)), with: .color(color.opacity(0.4)))
                return
            }
            let step: CGFloat = 2
            var x: CGFloat = 0
            while x < size.width {
                let t0 = Double(x / size.width) * duration
                let t1 = Double((x + step) / size.width) * duration
                var level = -80.0
                if let from = sourceTime(t0), let to = sourceTime(t1) {
                    let low = max(0, Int(min(from, to) / AudioLevels.windowSeconds))
                    let high = min(levels.count - 1, max(low, Int(max(from, to) / AudioLevels.windowSeconds)))
                    if low <= high, low < levels.count { level = levels[low...high].max() ?? -80 }
                }
                let amplitude = CGFloat(max(0, min(1, (level + 60) / 60))) * size.height
                let height = max(1, amplitude)
                context.fill(Path(CGRect(x: x, y: (size.height - height) / 2, width: 1.4, height: height)), with: .color(color))
                x += step
            }
        }
        .allowsHitTesting(false)
    }
}

/// Proposed cuts (long pauses and restarts), drawn over the Video track as dashed orange stretches. Hover one to cut
/// it or dismiss it. Cutting is one undoable step.
private struct TightenMarks: View {
    @ObservedObject var model: StudioModel
    let pps: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.pendingTighten) { candidate in
                ForEach(Array(model.tightenSpans(for: candidate).enumerated()), id: \.offset) { _, span in
                    TightenMark(model: model, candidate: candidate)
                        .frame(width: max(8, span.length * pps), height: Metrics.row)
                        .offset(x: span.start * pps)
                }
            }
        }
    }
}

private struct TightenMark: View {
    @ObservedObject var model: StudioModel
    let candidate: EditSuggestion
    @State private var hovering = false

    private var title: String { candidate.kind == .silence ? "Pause" : "Restart" }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.orange.opacity(hovering ? 0.5 : 0.32))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .overlay {
                if hovering {
                    HStack(spacing: 6) {
                        Button { model.cutTighten([candidate]) } label: { Image(systemName: "scissors") }
                            .help("Cut this \(title.lowercased()) out of the video (you can undo it)")
                        Button { model.dismissTighten(candidate) } label: { Image(systemName: "xmark") }
                            .help("Keep it: dismiss this suggestion")
                    }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator))
                    .fixedSize()
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help("\(title): \(candidate.reason). Hover to cut it or keep it.")
            .accessibilityLabel("\(title) suggestion, \(candidate.reason)")
    }
}
