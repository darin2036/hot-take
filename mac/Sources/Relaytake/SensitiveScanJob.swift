import AVFoundation
import CoreGraphics
import Foundation
import RelaytakeCore
import SwiftUI
import Vision

/// Looks through a recording for sensitive text (email addresses, phone numbers, keys, card numbers and the
/// person's own words) so it can be blurred. It runs only when the person starts it, reads the text with the
/// system's on-device recognizer, and sends nothing off this Mac. What it finds is listed for review; only
/// the findings the person keeps become blur marks.
@MainActor
final class SensitiveScanJob: ObservableObject {
    /// 0...1 while scanning; nil when idle.
    @Published private(set) var progress: Double?
    @Published private(set) var status = ""
    /// Nil until a scan finishes.
    @Published private(set) var findings: [SensitiveFinding]?
    @Published var chosen = Set<UUID>()
    @Published private(set) var note = ""

    private var task: Task<Void, Never>?

    var isRunning: Bool { progress != nil }

    func run(url: URL, duration: Double, terms: [String]) {
        guard !isRunning, duration > 0 else { return }
        findings = nil
        chosen = []
        note = ""
        progress = 0
        status = "Getting ready…"
        task = Task {
            defer { progress = nil; task = nil }
            do {
                let sightings = try await Self.read(url: url, duration: duration, terms: terms) { done, total in
                    self.progress = Double(done) / Double(max(1, total))
                    self.status = "Reading frame \(done) of \(total)…"
                }
                let found = SensitiveScan.findings(from: sightings, duration: duration)
                findings = found
                chosen = Set(found.map(\.id))
                if found.isEmpty { note = "Nothing sensitive was found. Small or blurry text can be missed, so watch it through before you share it." }
            } catch is CancellationError {
                note = "Stopped. Nothing was blurred."
            } catch {
                note = "Could not look through the recording: \(error.localizedDescription)"
            }
        }
    }

    func cancel() { task?.cancel() }

    func reset() {
        cancel()
        findings = nil
        chosen = []
        note = ""
    }

    // MARK: Reading the frames

    /// Samples the recording every `SensitiveScan.interval` seconds and reads the text on each frame. A frame
    /// that looks the same as the one before (most of a screen recording) reuses what was read from it.
    nonisolated private static func read(
        url: URL, duration: Double, terms: [String], progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws -> [SensitiveSighting] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let step = SensitiveScan.interval
        let times = stride(from: 0.0, to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var sightings: [SensitiveSighting] = []
        var previous: (thumbnail: [UInt8], found: [SensitiveSighting])?
        var done = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            done += 1
            let time = result.requestedTime.seconds
            guard let image = try? result.image else { continue }
            let thumbnail = Self.thumbnail(image)
            let found: [SensitiveSighting]
            if let previous, Self.looksSame(previous.thumbnail, thumbnail) {
                found = previous.found.map { var copy = $0; copy.time = time; return copy }
            } else {
                found = try Self.recognize(image, time: time, terms: terms)
            }
            sightings += found
            previous = (thumbnail, found)
            await progress(done, times.count)
        }
        try Task.checkCancellation()
        return sightings
    }

    nonisolated private static func recognize(_ image: CGImage, time: Double, terms: [String]) throws -> [SensitiveSighting] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Correction would "fix" keys and addresses into words, and then they would not match.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        var found: [SensitiveSighting] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            for match in SensitiveText.matches(in: candidate.string, terms: terms) {
                // Vision measures from the bottom-left; marks measure from the top-left.
                let box = (try? candidate.boundingBox(for: match.range))?.boundingBox ?? observation.boundingBox
                let rect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                found.append(SensitiveSighting(kind: match.kind, text: match.text, time: time, rect: rect))
            }
        }
        return found
    }

    /// A tiny grey copy of the frame, for telling whether anything on screen changed.
    nonisolated private static func thumbnail(_ image: CGImage) -> [UInt8] {
        let width = 96, height = 54
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// Whether two thumbnails match closely enough that the text on them is the same. Any small patch that
    /// changed (a line of text scrolling in, say) counts as a change, however still the rest is.
    nonisolated private static func looksSame(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return !zip(a, b).contains { abs(Int($0) - Int($1)) > 6 }
    }
}

/// Starts a scan, shows its progress, and lists what it found for the person to keep or drop.
struct SensitiveScanSheet: View {
    @ObservedObject var model: StudioModel
    @ObservedObject var job: SensitiveScanJob
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sensitiveTerms") private var terms = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find Sensitive Info").font(.headline)
            if let progress = job.progress {
                scanning(progress)
            } else if let findings = job.findings, !findings.isEmpty {
                review(findings)
            } else {
                start
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var start: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hot Take reads the text on screen throughout the recording and lists email addresses, phone numbers, card and ID numbers, keys and passwords it finds. You choose which ones to blur. It runs on this Mac only.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Also blur these words").font(.callout.weight(.medium))
                TextField("Names, a client, a hostname, separated by commas", text: $terms)
                    .textFieldStyle(.roundedBorder)
            }
            Text("It can miss small, blurry or briefly shown text. Always watch the video through before you share it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !job.note.isEmpty {
                Text(job.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Look Through Recording") {
                    model.scanForSensitiveInfo(terms: SensitiveText.terms(from: terms))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.ready)
            }
        }
    }

    private func scanning(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: progress)
            HStack {
                Text(job.status).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(progress, format: .percent.precision(.fractionLength(0))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Spacer()
                Button("Stop") { job.cancel() }.keyboardShortcut(.cancelAction)
            }
        }
    }

    private func review(_ findings: [SensitiveFinding]) -> some View {
        let shown = findings.compactMap { finding in
            model.sensitiveBlurs(for: finding).first.map { (finding: finding, at: $0.start) }
        }
        let hidden = findings.count - shown.count
        let keeping = shown.filter { job.chosen.contains($0.finding.id) }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("Found \(shown.count) item\(shown.count == 1 ? "" : "s"). Untick any you want left as they are, then add the rest as blurs. Each one is an ordinary blur you can move, resize or delete.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            List(shown, id: \.finding.id) { item in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(
                        get: { job.chosen.contains(item.finding.id) },
                        set: { on in if on { job.chosen.insert(item.finding.id) } else { job.chosen.remove(item.finding.id) } }))
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.finding.kind.title).font(.callout.weight(.medium))
                        Text(SensitiveText.masked(item.finding.text)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(ChapterList.timestamp(item.at)) { model.seek(to: item.at) }
                        .buttonStyle(.link).monospacedDigit()
                        .help("Show this moment")
                }
            }
            .frame(height: 260)
            if hidden > 0 {
                Text("\(hidden) more \(hidden == 1 ? "was" : "were") only in parts you cut out.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Check the rest of the video yourself too: small or blurry text can be missed.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start Over") { job.reset() }
                Spacer()
                Button("Cancel") { job.reset(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add \(keeping) Blur\(keeping == 1 ? "" : "s")") {
                    model.addSensitiveBlurs(findings.filter { job.chosen.contains($0.id) })
                    job.reset()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keeping == 0)
            }
        }
    }
}
