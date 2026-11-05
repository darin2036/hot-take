import Foundation

// An edit an agent describes in one go: cut the slow parts, zoom in on the click that matters, add a caption or an arrow.
// Every time in the list is a moment of the original recording (seconds, or the name of a marker, optionally with an
// offset like "Open Studio+1.5"), so the agent never has to work out where an earlier cut moved things. The applier turns
// the list into the same Studio edits a person would make by hand, and an autosaved draft carries them into the Studio.

/// A moment of the original recording: seconds, or a marker's name with an optional `+`/`-` offset in seconds.
public enum TimeRef: Codable, Equatable, Sendable {
    case seconds(Double)
    case marker(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            self = .seconds(seconds)
        } else {
            self = .marker(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .seconds(let value): try container.encode(value)
        case .marker(let name): try container.encode(name)
        }
    }

    /// The moment in seconds, or nil when no marker has that name.
    public func resolve(markers: [AgentMarker]) -> Double? {
        switch self {
        case .seconds(let value):
            return value.isFinite ? value : nil
        case .marker(let text):
            func find(_ name: String) -> Double? {
                markers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.time
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if let time = find(trimmed) { return time }
            // "Name+1.5" or "Name-0.5"
            if let split = trimmed.lastIndex(where: { $0 == "+" || $0 == "-" }), split > trimmed.startIndex,
               let offset = Double(trimmed[split...].replacingOccurrences(of: "+", with: "")),
               let time = find(String(trimmed[..<split]).trimmingCharacters(in: .whitespaces)) {
                return time + offset
            }
            return nil
        }
    }

    var label: String {
        switch self {
        case .seconds(let value): String(format: "%.1fs", value)
        case .marker(let name): "“\(name)”"
        }
    }
}

public struct EditList: Codable, Equatable, Sendable {
    /// Footage to remove: the parts where the demo waited or searched. Overlapping cuts are merged.
    public struct Cut: Codable, Equatable, Sendable {
        public var from: TimeRef
        public var to: TimeRef
        public init(from: TimeRef, to: TimeRef) { self.from = from; self.to = to }
    }

    /// A zoom. Without `x` and `y` it looks at the click nearest `at` (within three seconds), else the middle.
    public struct Zoom: Codable, Equatable, Sendable {
        public var at: TimeRef
        public var duration: Double?
        public var x: Double?
        public var y: Double?
        public var scale: Double?
        public init(at: TimeRef, duration: Double? = nil, x: Double? = nil, y: Double? = nil, scale: Double? = nil) {
            self.at = at; self.duration = duration; self.x = x; self.y = y; self.scale = scale
        }
    }

    /// A caption box. `position` is `top`, `center` or `bottom` (the default).
    public struct Text: Codable, Equatable, Sendable {
        public var text: String
        public var at: TimeRef
        public var duration: Double?
        public var position: String?
        public init(text: String, at: TimeRef, duration: Double? = nil, position: String? = nil) {
            self.text = text; self.at = at; self.duration = duration; self.position = position
        }
    }

    /// An `arrow`, `box` or `blur`. Coordinates are 0...1 from the top-left of the picture: an arrow runs from
    /// (x1, y1) to its head at (x2, y2); a box or blur fills the rectangle between the corners.
    public struct Shape: Codable, Equatable, Sendable {
        public var kind: String
        public var at: TimeRef
        public var duration: Double?
        public var x1: Double
        public var y1: Double
        public var x2: Double
        public var y2: Double
        public init(kind: String, at: TimeRef, duration: Double? = nil, x1: Double, y1: Double, x2: Double, y2: Double) {
            self.kind = kind; self.at = at; self.duration = duration
            self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        }
    }

    /// Keep only this stretch; everything before and after is cut.
    public var keep: Cut?
    public var cuts: [Cut]?
    public var zooms: [Zoom]?
    public var texts: [Text]?
    public var shapes: [Shape]?
    /// What to say at each marker, by marker name. Used for the narration script, not drawn on the video.
    public var narration: [String: String]?
    /// Zoom in around each group of recorded clicks, as the Studio's Auto Zoom does. Zooms listed below are added to these.
    public var autoZoom: Bool?
    /// With `autoZoom`, keep no more than about this many of the automatic zooms in each minute (the rest are dropped).
    public var maxZoomsPerMinute: Double?
    /// Fold each `Retake: Name` marker into the step it redoes: the failed attempt is cut and the retake takes the step's name.
    /// On unless this is false.
    public var autoRetakes: Bool?
    /// Turn the `narration` lines into captions drawn in the picture, a `.vtt` file and the saved copy's transcript, for a demo with no
    /// spoken audio. Each line fills the part of the video that begins at its marker. Needs `narration`.
    public var narrationCaptions: Bool?
    /// With `narrationCaptions`: `classic` (the default), `bold`, `minimal` or `highlight`.
    public var captionStyle: String?
    /// With `narrationCaptions`: `bottom` (the default), `middle` or `top`.
    public var captionPosition: String?
    /// Draw a ring at each recorded click.
    public var clickRings: Bool?
    /// Markers become chapters of the saved copy unless this is false.
    public var chapters: Bool?
    /// Replace edits already in the take's draft. Without it, a take that already has edits is left alone.
    public var replace: Bool?

    public init(
        keep: Cut? = nil, cuts: [Cut]? = nil, zooms: [Zoom]? = nil, texts: [Text]? = nil, shapes: [Shape]? = nil,
        autoZoom: Bool? = nil, clickRings: Bool? = nil, narration: [String: String]? = nil, chapters: Bool? = nil,
        replace: Bool? = nil, maxZoomsPerMinute: Double? = nil, autoRetakes: Bool? = nil, narrationCaptions: Bool? = nil,
        captionStyle: String? = nil, captionPosition: String? = nil
    ) {
        self.narrationCaptions = narrationCaptions; self.captionStyle = captionStyle; self.captionPosition = captionPosition
        self.maxZoomsPerMinute = maxZoomsPerMinute; self.autoRetakes = autoRetakes
        self.autoZoom = autoZoom; self.clickRings = clickRings
        self.keep = keep; self.cuts = cuts; self.zooms = zooms; self.texts = texts; self.shapes = shapes
        self.narration = narration; self.chapters = chapters; self.replace = replace
    }
}

/// One stretch of the edited video that begins at a marker: the room an agent's or a person's narration has.
public struct NarrationBeat: Equatable, Sendable {
    public var name: String
    public var start: Double
    public var end: Double
    public var text: String?

    public var length: Double { end - start }
}

public struct EditListOutcome: Equatable, Sendable {
    public var applied: [String] = []
    public var warnings: [String] = []
    public var beats: [NarrationBeat] = []
}

public enum EditListApplier {
    /// How far from `at` a click can be and still be the one a zoom looks at.
    public static let clickReach = 3.0

    /// Applies `list` to `project`, which must have no edits yet (cuts are made on the original's timeline). Anything
    /// that cannot be done is skipped and reported, never half-applied.
    public static func apply(
        _ list: EditList, to start: StudioProject, markers allMarkers: [AgentMarker], clicks: [ClickEvent]
    ) -> (project: StudioProject, outcome: EditListOutcome) {
        var project = start
        var outcome = EditListOutcome()
        let duration = project.cuts.duration

        // 0. Retakes: each failed attempt is cut and its retake stands for the step.
        var markers = allMarkers
        var retakeCuts: [TimeSpan] = []
        if list.autoRetakes != false {
            let resolved = AgentRetakes.resolve(allMarkers)
            markers = resolved.markers
            retakeCuts = resolved.cuts.map { TimeSpan(start: max(0, $0.start), end: min(duration, $0.end)) }
            outcome.warnings += resolved.warnings
            if !retakeCuts.isEmpty {
                outcome.applied.append(retakeCuts.count == 1 ? "Cut 1 failed attempt that was redone as a retake." : "Cut \(retakeCuts.count) failed attempts that were redone as retakes.")
            }
        }

        // 1. Cuts, in the original's time. Merged, then removed last-to-first so earlier ones do not move.
        var spans: [TimeSpan] = []
        func span(_ cut: EditList.Cut) -> TimeSpan? {
            guard let from = cut.from.resolve(markers: markers) else { outcome.warnings.append("No marker named \(cut.from.label); that cut was skipped."); return nil }
            guard let to = cut.to.resolve(markers: markers) else { outcome.warnings.append("No marker named \(cut.to.label); that cut was skipped."); return nil }
            let low = max(0, min(from, to)), high = min(duration, max(from, to))
            guard high - low >= EditModel.minimumSegment else {
                outcome.warnings.append("The cut from \(cut.from.label) to \(cut.to.label) is too short or outside the recording; skipped.")
                return nil
            }
            return TimeSpan(start: low, end: high)
        }
        if let keep = list.keep, let kept = span(keep) {
            if kept.start > 0 { spans.append(TimeSpan(start: 0, end: kept.start)) }
            if kept.end < duration { spans.append(TimeSpan(start: kept.end, end: duration)) }
        }
        for cut in list.cuts ?? [] { if let found = span(cut) { spans.append(found) } }
        spans += retakeCuts.filter { $0.end - $0.start >= EditModel.minimumSegment }
        let merged = mergedSpans(spans)
        var removed = 0.0
        for range in merged.reversed() {
            do {
                try project.remove(range)
                removed += range.length
            } catch {
                outcome.warnings.append("Could not cut \(timeLabel(range.start))–\(timeLabel(range.end)): \(error.localizedDescription)")
            }
        }
        if !merged.isEmpty, removed > 0 {
            outcome.applied.append(String(format: "Cut %.1f s in %d place%@; the video is now %.1f s.", removed, merged.count, merged.count == 1 ? "" : "s", project.outputDuration))
        }

        func output(_ ref: TimeRef, _ what: String) -> Double? {
            guard let source = ref.resolve(markers: markers) else {
                outcome.warnings.append("No marker named \(ref.label); that \(what) was skipped.")
                return nil
            }
            guard let time = project.cuts.outputTime(forSource: source) else {
                outcome.warnings.append("The \(what) at \(ref.label) falls in a part that was cut out; skipped.")
                return nil
            }
            return time
        }

        if list.clickRings == true {
            project.setClickHighlights(on: true, clicks: clicks)
            outcome.applied.append(clicks.isEmpty ? "Click rings are on, but this take has no recorded clicks." : "Added rings at each click.")
        }
        if list.autoZoom == true {
            project.generateZooms(from: clicks)
            if let limit = list.maxZoomsPerMinute, limit > 0 {
                let before = project.zooms.count
                project.zooms = ZoomCap.thinned(project.zooms, maxPerMinute: limit)
                if project.zooms.count < before {
                    outcome.applied.append("Kept \(project.zooms.count) of \(before) automatic zooms (at most \(Int(limit)) a minute).")
                }
            }
            outcome.applied.append(project.zooms.isEmpty ? "Auto zoom found no clicks to zoom on." : "Added \(project.zooms.count) zoom\(project.zooms.count == 1 ? "" : "s") on the clicks.")
        }

        // 2. Zooms.
        var zoomCount = 0
        for zoom in list.zooms ?? [] {
            guard let at = output(zoom.at, "zoom") else { continue }
            let source = zoom.at.resolve(markers: markers) ?? 0
            var x = zoom.x, y = zoom.y
            if x == nil || y == nil, let click = clicks.min(by: { abs($0.time - source) < abs($1.time - source) }),
               abs(click.time - source) <= clickReach {
                x = x ?? click.x
                y = y ?? click.y
            }
            let id = project.addZoom(at: at, scale: zoom.scale ?? 1.8)
            let length = zoom.duration ?? 2.5
            project.updateZoom(id) {
                $0.start = at
                $0.end = at + max(ZoomSegment.minimumLength, length)
                $0.x = x ?? 0.5
                $0.y = y ?? 0.5
            }
            zoomCount += 1
        }
        if zoomCount > 0 { outcome.applied.append("Added \(zoomCount) zoom\(zoomCount == 1 ? "" : "s").") }

        // 3. Captions.
        var textCount = 0
        for item in list.texts ?? [] {
            guard let at = output(item.at, "caption") else { continue }
            let id = project.addText(at: at, text: item.text)
            let y: Double
            switch item.position?.lowercased() {
            case "top": y = 0.12
            case "center", "middle": y = 0.5
            default: y = 0.82
            }
            project.updateText(id) {
                $0.start = at
                $0.end = at + max(ZoomSegment.minimumLength, item.duration ?? 3)
                $0.y = y
            }
            textCount += 1
        }
        if textCount > 0 { outcome.applied.append("Added \(textCount) caption\(textCount == 1 ? "" : "s").") }

        // 4. Arrows, boxes and blurs.
        var shapeCount = 0
        for item in list.shapes ?? [] {
            guard let kind = ShapeOverlay.Kind(rawValue: item.kind.lowercased()) else {
                outcome.warnings.append("“\(item.kind)” is not a mark; use arrow, box or blur.")
                continue
            }
            guard let at = output(item.at, kind.title.lowercased()) else { continue }
            let id = project.addShape(kind, at: at)
            project.updateShape(id) {
                $0.start = at
                $0.end = at + max(ShapeOverlay.minimumLength, item.duration ?? 4)
                $0.x1 = min(1, max(0, item.x1)); $0.y1 = min(1, max(0, item.y1))
                $0.x2 = min(1, max(0, item.x2)); $0.y2 = min(1, max(0, item.y2))
            }
            shapeCount += 1
        }
        if shapeCount > 0 { outcome.applied.append("Added \(shapeCount) mark\(shapeCount == 1 ? "" : "s").") }

        outcome.beats = beats(markers: markers, narration: list.narration ?? [:], cuts: project.cuts, warnings: &outcome.warnings)

        // 5. Narration as captions.
        if list.narrationCaptions == true {
            let style = list.captionStyle.flatMap { CaptionStyle(rawValue: $0.lowercased()) } ?? .classic
            let position = list.captionPosition.flatMap { CaptionPosition(rawValue: $0.lowercased()) } ?? .bottom
            if let named = list.captionStyle, CaptionStyle(rawValue: named.lowercased()) == nil {
                outcome.warnings.append("“\(named)” is not a caption style; used classic. Choose classic, bold, minimal or highlight.")
            }
            if let named = list.captionPosition, CaptionPosition(rawValue: named.lowercased()) == nil {
                outcome.warnings.append("“\(named)” is not a caption position; used bottom. Choose bottom, middle or top.")
            }
            let cues = NarrationCaptions.sourceCues(beats: outcome.beats, cuts: project.cuts)
            if cues.isEmpty {
                outcome.warnings.append("narrationCaptions is on, but no narration line landed on the video, so there are no captions. Write narration for the markers.")
            } else {
                project.captions = StudioCaptions(style: style, position: position, cues: cues, fromNarration: true)
                outcome.applied.append("Narration became \(cues.count) caption line\(cues.count == 1 ? "" : "s") drawn in the video, and the copy's transcript and captions file.")
            }
        }
        if list.chapters != false, !markers.isEmpty { outcome.applied.append("Markers will be chapters of the saved copy.") }
        return (project, outcome)
    }

    /// Union of overlapping or touching spans, in order.
    static func mergedSpans(_ spans: [TimeSpan]) -> [TimeSpan] {
        var result: [TimeSpan] = []
        for span in spans.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, span.start <= last.end + 1e-9 {
                result[result.count - 1].end = max(last.end, span.end)
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// Where each marker falls on the edited video. A marker inside a cut moves to where the next kept footage begins.
    static func beats(markers: [AgentMarker], narration: [String: String], cuts: EditModel, warnings: inout [String]) -> [NarrationBeat] {
        let total = cuts.keptDuration
        let starts: [(name: String, time: Double)] = markers.sorted { $0.time < $1.time }.compactMap { marker in
            if let time = cuts.outputTime(forSource: marker.time) { return (marker.name, time) }
            var elapsed = 0.0
            for segment in cuts.segments {
                if segment.start >= marker.time { return (marker.name, elapsed) }
                elapsed += segment.length
            }
            return nil
        }
        var result: [NarrationBeat] = []
        for (index, item) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].time : total
            // A part that was cut away on purpose (the wait for something to load) has no room left and drops out.
            guard end - item.time > 0.05 else { continue }
            let line = narration.first { key, _ in
                key.caseInsensitiveCompare(item.name) == .orderedSame
                    || AgentRetakes.beatName(of: key)?.caseInsensitiveCompare(item.name) == .orderedSame
            }?.value
            result.append(NarrationBeat(name: item.name, start: item.time, end: end, text: line))
        }
        for name in narration.keys where !markers.contains(where: { marker in
            let target = AgentRetakes.beatName(of: name) ?? name
            return marker.name.caseInsensitiveCompare(name) == .orderedSame || marker.name.caseInsensitiveCompare(target) == .orderedSame
        }) {
            warnings.append("Narration for “\(name)” was not used: no marker has that name.")
        }
        return result
    }
}

/// The voice-over script, laid out against the edited video so a person (or a voice tool) can read each line in the room it has.
public enum NarrationScript {
    /// A calm reading pace.
    public static let wordsPerSecond = 2.5

    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func markdown(title: String, beats: [NarrationBeat]) -> String {
        var out = "# Narration script: \(title)\n\nTimes are on the edited video. Each line should fit the time its part of the video lasts (about \(wordsPerSecond) words a second).\n"
        for beat in beats {
            out += "\n## \(clock(beat.start))–\(clock(beat.end)) · \(beat.name) (\(Int(beat.length.rounded())) s)\n\n"
            guard let text = beat.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                out += "_No narration written for this part._\n"
                continue
            }
            let words = text.split(whereSeparator: \.isWhitespace).count
            let room = Int((beat.length * wordsPerSecond).rounded(.down))
            out += text + "\n"
            if words > room + max(2, room / 10) {
                out += "\n> Too long for this part: \(words) words, room for about \(room). Shorten the line or lengthen the part.\n"
            }
        }
        return out
    }
}

/// Applies an agent's edit list to one take and saves the result as the take's Studio draft, so the person can open it, look it
/// over and change it. Never overwrites edits that are already in the draft unless the list says `replace`.
public enum AgentEdit {
    public struct Done: Equatable, Sendable {
        public var project: StudioProject
        public var outcome: EditListOutcome
        /// Where the narration script was written, if the markers gave it any parts.
        public var narration: URL?
    }

    public struct Failure: Error, Equatable, Sendable {
        public var message: String
        public var warnings: [String] = []
    }

    public static func run(
        _ list: EditList, files: TakeFiles, duration: Double, camera: CameraSource?, title: String,
        markers: [AgentMarker], clicks: [ClickEvent]
    ) -> Result<Done, Failure> {
        let store = StudioDraftStore(files: files)
        if list.replace != true, let draft = store.load(),
           let existing = draft.project(duration: duration, cameraSource: camera), existing.isEdited {
            return .failure(Failure(message: "That take already has edits in its Studio draft. Send \"replace\": true to start over from the original."))
        }
        let (project, outcome) = EditListApplier.apply(
            list, to: StudioProject(duration: duration, cameraSource: camera), markers: markers, clicks: clicks)
        guard project.isEdited else {
            return .failure(Failure(message: "Nothing in the edit list could be applied.", warnings: outcome.warnings))
        }
        guard let data = store.encode(StudioDraft(project: project, playhead: 0)), store.write(data) else {
            return .failure(Failure(message: "The edit could not be saved beside the take."))
        }
        var narration: URL?
        if !outcome.beats.isEmpty {
            let script = NarrationScript.markdown(title: title.isEmpty ? files.baseName : title, beats: outcome.beats)
            if (try? script.write(to: files.narration, atomically: true, encoding: .utf8)) != nil { narration = files.narration }
        }
        return .success(Done(project: project, outcome: outcome, narration: narration))
    }
}
