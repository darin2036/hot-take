import AVFoundation
import CoreGraphics
import Foundation

// "Record for an agent": a take turned into a request a coding agent (Claude Code, Codex, Cursor…) can act on.
// What was said is laid out beside a picture of the screen at each click, with a ring where the click was, and
// optionally a goal and steps written by the on-device model. It is a folder of ordinary files beside the take,
// made on this Mac; nothing is sent anywhere. Pasting it into an agent is the user's choice.

public enum AgentBrief {
    /// A moment to take a picture at, and the click that prompted it (nil for one taken while talking).
    public struct Moment: Equatable, Sendable {
        public var time: Double
        public var click: ClickEvent?

        public init(time: Double, click: ClickEvent? = nil) {
            self.time = time
            self.click = click
        }
    }

    /// What the person wants done, as the on-device model read it from the narration.
    public struct Request: Equatable, Sendable {
        public var goal: String
        public var steps: [String]

        public init(goal: String, steps: [String]) {
            self.goal = goal
            self.steps = steps
        }
    }

    /// Pictures cost an agent context, so a long walkthrough is thinned to this many.
    public static let maxPictures = 20
    /// Pictures are scaled down to fit this, which is plenty for reading a screen.
    public static let maxPictureSide = 1600
    public static let promptFileName = "PROMPT.md"
    public static let picturesFolder = "frames"

    /// One moment per click (a double-click is one), plus one in each spoken line that has no click near it, so a
    /// walkthrough done by talking over the screen still gets pictures. Clicks are kept over talk when thinning.
    public static func moments(clicks: [ClickEvent], transcript: [CaptionSegment], duration: Double, limit: Int = maxPictures) -> [Moment] {
        guard duration > 0, limit > 0 else { return [] }
        var clicked: [Moment] = []
        for click in clicks.sorted(by: { $0.time < $1.time }) where click.time >= 0 && click.time <= duration {
            if let last = clicked.last, click.time - last.time < 1 { continue }
            clicked.append(Moment(time: click.time, click: click))
        }
        var spoken: [Moment] = []
        for segment in transcript where segment.end > segment.start {
            let middle = min(duration, (segment.start + segment.end) / 2)
            let nearClick = clicked.contains { $0.time >= segment.start - 1 && $0.time <= segment.end + 1 }
            let nearOther = spoken.last.map { middle - $0.time < 2 } ?? false
            if !nearClick, !nearOther, middle >= 0 { spoken.append(Moment(time: middle)) }
        }
        if clicked.isEmpty, spoken.isEmpty { return [Moment(time: duration / 2)] }
        let keptClicks = thinned(clicked, to: limit)
        let keptSpoken = thinned(spoken, to: limit - keptClicks.count)
        return (keptClicks + keptSpoken).sorted { $0.time < $1.time }
    }

    /// Evenly spaced members of `items`, at most `count`, keeping the first and last.
    static func thinned<T>(_ items: [T], to count: Int) -> [T] {
        guard count > 0 else { return [] }
        guard items.count > count else { return items }
        if count == 1 { return [items[0]] }
        return (0..<count).map { items[Int((Double($0) * Double(items.count - 1) / Double(count - 1)).rounded())] }
    }

    /// The spoken lines that go with each moment: each line goes to the moment nearest its middle, so talk just
    /// before a click and talk just after it both stay with that picture. Lines are in order within each moment.
    public static func narration(for moments: [Moment], transcript: [CaptionSegment]) -> [[CaptionSegment]] {
        var groups = Array(repeating: [CaptionSegment](), count: moments.count)
        guard !moments.isEmpty else { return groups }
        for segment in transcript {
            let middle = (segment.start + segment.end) / 2
            let nearest = moments.indices.min { abs(moments[$0].time - middle) < abs(moments[$1].time - middle) } ?? 0
            groups[nearest].append(segment)
        }
        return groups
    }

    /// "1:05", or "1:02:05" past an hour.
    public static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// "03-1m05s.png": numbered so they sort in order, with the moment in the name and no spaces.
    public static func pictureName(number: Int, of total: Int, time: Double) -> String {
        let digits = max(2, String(total).count)
        let whole = Int(max(0, time).rounded(.down))
        return String(format: "%0\(digits)d-%dm%02ds.png", number, whole / 60, whole % 60)
    }

    /// The request as Markdown. `pictures` holds the path written for each moment's picture (relative in the
    /// saved file, absolute in what is copied, so an agent can open them wherever it runs).
    public static func markdown(
        title: String, created: Date, duration: Double, captureKind: String?, moments: [Moment], pictures: [String],
        transcript: [CaptionSegment], request: Request?
    ) -> String {
        var lines: [String] = []
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("# \(name.isEmpty ? "Screen recording" : name)")
        lines.append("")
        let what = captureKind.map { " of a \($0 == "area" ? "screen area" : $0)" } ?? ""
        lines.append(
            "This is a \(clock(duration)) screen recording\(what), made \(created.formatted(date: .long, time: .shortened)), "
                + "turned into a request for you. Under each picture is what the person said around that moment; "
                + "a red ring marks where they clicked. Open the pictures before acting, and ask if something is unclear "
                + "rather than guessing.")

        if let request, !request.goal.isEmpty || !request.steps.isEmpty {
            lines.append("")
            lines.append("## What they want")
            if !request.goal.isEmpty {
                lines.append("")
                lines.append(request.goal)
            }
            if !request.steps.isEmpty {
                lines.append("")
                for (index, step) in request.steps.enumerated() { lines.append("\(index + 1). \(step)") }
            }
            lines.append("")
            lines.append("_Written from the narration by an on-device model; the walkthrough below is the source of truth._")
        }

        if !moments.isEmpty {
            lines.append("")
            lines.append("## Walkthrough")
            let said = narration(for: moments, transcript: transcript)
            for (index, moment) in moments.enumerated() {
                lines.append("")
                var heading = "### \(index + 1). At \(clock(moment.time))"
                if let click = moment.click {
                    heading += " — clicked \(Int((click.x * 100).rounded()))% across, \(Int((click.y * 100).rounded()))% down"
                }
                lines.append(heading)
                if index < pictures.count {
                    lines.append("")
                    lines.append("![Picture \(index + 1) at \(clock(moment.time))](<\(pictures[index])>)")
                }
                let words = said[index].map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty {
                    lines.append("")
                    lines.append("> \(words)")
                }
            }
        }

        let spoken = transcript.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        lines.append("")
        lines.append("## Full transcript")
        lines.append("")
        if spoken.isEmpty {
            lines.append("_Nothing was said, or there is no transcript._")
        } else {
            for segment in spoken { lines.append("- [\(clock(segment.start))] \(segment.text)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `image` with a ring drawn where `click` was (a 0…1 position from the top-left).
    public static func marked(_ image: CGImage, click: ClickEvent) -> CGImage {
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: bounds)
        let radius = max(12, Double(min(width, height)) * 0.03)
        let center = CGPoint(x: click.x * Double(width), y: (1 - click.y) * Double(height))
        let ring = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        // A white halo under the red ring keeps it visible on red or dark screens.
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        context.setLineWidth(radius * 0.4)
        context.strokeEllipse(in: ring)
        context.setStrokeColor(CGColor(red: 0.92, green: 0.1, blue: 0.1, alpha: 1))
        context.setLineWidth(radius * 0.22)
        context.strokeEllipse(in: ring)
        return context.makeImage() ?? image
    }

    /// What `write` made: the folder, its prompt file, and the prompt with absolute picture paths for copying.
    public struct Output: Sendable {
        public var folder: URL
        public var promptFile: URL
        public var pictures: [URL]
        public var copyText: String
    }

    /// Writes the request for `files` into its folder beside the take (replacing an earlier one): a picture at each
    /// moment and `PROMPT.md`. The folder appears only when complete.
    public static func write(
        for files: TakeFiles, metadata: TakeMetadata, request: Request?,
        fileManager: FileManager = .default, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Output {
        let asset = AVURLAsset(url: files.video)
        let duration = try await asset.load(.duration).seconds
        let moments = moments(clicks: metadata.clicks, transcript: metadata.transcript, duration: duration)

        let folder = files.agentDirectory
        let parent = folder.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging.appendingPathComponent(picturesFolder), withIntermediateDirectories: true)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPictureSide, height: maxPictureSide)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var names: [String] = []
        for (index, moment) in moments.enumerated() {
            try Task.checkCancellation()
            // Right at the very end there may be no frame; the last one will do.
            let at = min(moment.time, max(0, duration - 0.04))
            var image = try await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)).image
            if let click = moment.click { image = marked(image, click: click) }
            let name = pictureName(number: index + 1, of: moments.count, time: moment.time)
            try Screenshot.writePNG(image, to: staging.appendingPathComponent(picturesFolder).appendingPathComponent(name))
            names.append(name)
            progress(Double(index + 1) / Double(max(1, moments.count)))
        }

        func prompt(_ paths: [String]) -> String {
            markdown(
                title: metadata.title, created: metadata.created, duration: duration, captureKind: metadata.captureKind,
                moments: moments, pictures: paths, transcript: metadata.transcript, request: request)
        }
        try prompt(names.map { "\(picturesFolder)/\($0)" })
            .write(to: staging.appendingPathComponent(promptFileName), atomically: true, encoding: .utf8)

        if fileManager.fileExists(atPath: folder.path) {
            _ = try fileManager.replaceItemAt(folder, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: folder)
        }
        let pictures = names.map { folder.appendingPathComponent(picturesFolder).appendingPathComponent($0) }
        return Output(
            folder: folder, promptFile: folder.appendingPathComponent(promptFileName), pictures: pictures,
            copyText: prompt(pictures.map(\.path)))
    }
}

/// Asking the on-device model what the person in a walkthrough wants done, and reading its reply.
public enum AgentPrompt {
    public static let maxSteps = 10

    public static let instructions = """
        You turn the narration of a screen recording into a request for a software coding agent. \
        Use only what the transcript says. Do not invent file names, code, error messages, or details. \
        Reply in exactly this format and nothing else:
        GOAL: <one sentence saying what the person wants changed, fixed, or built>
        STEPS:
        - <one concrete thing to do>
        - <another, in the order the person described them>
        """

    public static func prompt(transcript: String) -> String {
        "Transcript of a screen recording:\n\n\(SummaryPrompt.clipped(transcript))"
    }

    /// Reads the GOAL:/STEPS: reply. Steps may be bulleted or numbered. Nil when nothing usable came back.
    public static func parse(_ reply: String) -> AgentBrief.Request? {
        var goal = ""
        var steps: [String] = []
        var inSteps = false
        for line in reply.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            let upper = line.uppercased()
            if upper.hasPrefix("GOAL:") {
                goal = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                inSteps = false
            } else if upper.hasPrefix("STEPS:") {
                inSteps = true
                let rest = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { steps.append(rest) }
            } else if inSteps {
                let step = stripMarker(line)
                if !step.isEmpty { steps.append(step) }
            }
        }
        goal = goal.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” "))
        steps = Array(steps.filter { $0.lowercased() != "none" }.prefix(maxSteps))
        return goal.isEmpty && steps.isEmpty ? nil : AgentBrief.Request(goal: goal, steps: steps)
    }

    /// "- x", "• x", "* x", "1. x" and "1) x" all become "x".
    private static func stripMarker(_ line: String) -> String {
        var text = Substring(line)
        if let first = text.first, "-•*".contains(first) {
            text = text.dropFirst()
        } else {
            let digits = text.prefix { $0.isNumber }
            if !digits.isEmpty, let after = text.dropFirst(digits.count).first, after == "." || after == ")" {
                text = text.dropFirst(digits.count + 1)
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
