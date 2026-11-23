import CryptoKit
import Foundation

// A voice that runs on this Mac: Kokoro, an open-weight speech model (Apache-2.0), run with Apple's MLX on the GPU. Nothing is sent
// anywhere to speak a line. The model and a handful of voices are one download the person approves, from Hugging Face, each file
// checked against a fixed SHA-256 before it is used. Nothing here runs the model or reaches the network; this file holds what is
// known about the files, the rules for splitting text the model can take, and the audio file it is written to.

public enum KokoroModel {
    /// The exact revision of `mlx-community/Kokoro-82M-bf16` the files below come from. A file that differs in a single byte is refused.
    public static let revision = "a71e4d38b236d968966a2002c4c895dbd12b1c3c"
    public static let host = "huggingface.co"
    public static let repository = "mlx-community/Kokoro-82M-bf16"
    /// Where the model's own page and license are.
    public static let page = URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!
    public static let sampleRate = 24_000

    public struct File: Equatable, Sendable {
        /// Path inside the repository, and inside the folder it is kept in.
        public let path: String
        public let size: Int
        public let sha256: String
    }

    public static let weights = File(
        path: "kokoro-v1_0.safetensors", size: 327_115_152, sha256: "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8")

    public struct Voice: Equatable, Identifiable, Sendable {
        /// The model's own name for it: the first letter is the accent (a American, b British) and the second the voice (f, m).
        public let id: String
        public let name: String
        public let sha256: String

        public var isBritish: Bool { id.hasPrefix("b") }
        public var accent: String { isBritish ? "British" : "American" }
        public var file: File { File(path: "voices/\(id).safetensors", size: 522_320, sha256: sha256) }
        /// "Heart · American"
        public var title: String { "\(name) · \(accent)" }
    }

    public static let voices: [Voice] = [
        Voice(id: "af_heart", name: "Heart", sha256: "2c1c733b0e6576c810e268d3e440c21dea4e0f0131a3ba4cfc98d7fe6136d094"),
        Voice(id: "af_bella", name: "Bella", sha256: "112d310468cbb3cf23404d3d0b50ad3adf017b87bf38bf9edd15f4ad572df6a3"),
        Voice(id: "af_nicole", name: "Nicole", sha256: "574656386022c81a029e9a72558191925f44c3de2dad2fa2e45751938557d062"),
        Voice(id: "af_sarah", name: "Sarah", sha256: "4940072182542f54c1035d1daf4c1cf3136ca9baa9ac57c8e006b4befcc50be6"),
        Voice(id: "am_michael", name: "Michael", sha256: "3940147ded35deba0bb52e8132f89b719298e0520258c34584358aa5a24da2ea"),
        Voice(id: "am_fenrir", name: "Fenrir", sha256: "9abed964b906c4cae6f404d9849e76260689aea862bc6ca85fc3f5207ba96538"),
        Voice(id: "am_puck", name: "Puck", sha256: "9a8c2e56413bd2063f814cb4c3885fc425876157369117c3f8258d03c8a9ad89"),
        Voice(id: "bf_emma", name: "Emma", sha256: "8878a75a6661305849eeb1d6293a7177250193616e161b4c3100636434dfe69f"),
        Voice(id: "bm_george", name: "George", sha256: "a3d9b8995cbbe5536f954b6be2a0f1f312f077118ba0d4d2178fc41dc8306672"),
        Voice(id: "bm_lewis", name: "Lewis", sha256: "e1e68013c21a141efe527aaec561e1174c2f5a6951b3bcecc8396adab315b247"),
    ]

    public static let defaultVoice = "af_heart"
    public static func voice(id: String?) -> Voice? { voices.first { $0.id == id } }

    /// A voice by the name an agent gave: its display name or id, ignoring case.
    public static func voice(named name: String?) -> Voice? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return voices.first { $0.id.caseInsensitiveCompare(name) == .orderedSame || $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Everything the download fetches: the model, then each voice.
    public static var files: [File] { [weights] + voices.map(\.file) }
    public static var totalBytes: Int { files.reduce(0) { $0 + $1.size } }

    /// The address of one file, fixed to `revision`. The path is one of the known files, so nothing else can be asked for.
    public static func url(for file: File) -> URL? {
        guard files.contains(file) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(repository)/resolve/\(revision)/\(file.path)"
        return components.url
    }

    /// The files in `folder` that are missing or the wrong size (a quick check; `sha256(of:)` is the full one, done as each is downloaded).
    public static func missing(in folder: URL, fileManager: FileManager = .default) -> [File] {
        files.filter { file in
            let attributes = try? fileManager.attributesOfItem(atPath: folder.appendingPathComponent(file.path).path)
            return (attributes?[.size] as? Int) != file.size
        }
    }

    /// The SHA-256 of a file, read in pieces so a large model is never all in memory.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let piece = try handle.read(upToCount: 1 << 20), !piece.isEmpty { hasher.update(data: piece) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Rules for feeding Kokoro and for the audio it gives back.
public enum LocalSpeech {
    /// The model takes at most 510 sounds at a time, which is a little over 200 characters of ordinary English, so text is spoken in pieces
    /// of up to this many characters.
    public static let maxChunkCharacters = 200
    /// Most characters an agent may have spoken in one edit with the voice on this Mac. It costs nothing, but it keeps the GPU busy.
    public static let agentCharacterLimit = 20_000
    /// Silence put between two pieces of one line.
    public static let gap = 0.12
    /// The fastest a line is asked to go. Past this the model starts to blur words.
    public static let speedRange = 0.7...1.3

    /// `text` as pieces the model can speak, each ending at a sentence end where it can. Sentences are packed together up to the limit (a
    /// little context makes the voice sound more connected); a sentence that is itself too long is broken at a comma or other pause,
    /// and failing that at a space.
    public static func chunks(of text: String, maxCharacters: Int = maxChunkCharacters) -> [String] {
        var pieces: [String] = []
        for sentence in NarrationCaptions.sentences(of: text) {
            pieces += sentence.count <= maxCharacters ? [sentence] : breakLong(sentence, maxCharacters)
        }
        var packed: [String] = []
        for piece in pieces {
            if let last = packed.last, last.count + 1 + piece.count <= maxCharacters { packed[packed.count - 1] = last + " " + piece }
            else { packed.append(piece) }
        }
        return packed
    }

    private static func breakLong(_ sentence: String, _ limit: Int) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() { if !current.isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)); current = "" } }
        // Words, with a pause mark kept on the word before it, so a break lands after a comma where one is near.
        for word in sentence.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if candidate.count > limit { flush(); current = String(word) } else { current = candidate }
            if current.count >= limit * 3 / 5, let last = current.last, ",;:—–".contains(last) { flush() }
        }
        flush()
        // A single "word" longer than the limit (a long address) is cut where it must be.
        return result.flatMap { piece -> [String] in
            guard piece.count > limit else { return [piece] }
            let characters = Array(piece)
            return stride(from: 0, to: characters.count, by: limit).map { String(characters[$0..<min($0 + limit, characters.count)]) }
        }
    }

    /// Pieces of audio joined with a short silence between them.
    public static func joined(_ pieces: [[Float]], sampleRate: Int = KokoroModel.sampleRate, gap: Double = LocalSpeech.gap) -> [Float] {
        var out: [Float] = []
        let silence = [Float](repeating: 0, count: Int(Double(sampleRate) * gap))
        for (index, piece) in pieces.enumerated() {
            if index > 0 { out += silence }
            out += piece
        }
        return out
    }

    /// The loudness a spoken line is brought to. The model's output is quiet (its peaks are around 0.35 to 0.55), so lines are
    /// raised by a fixed amount, less if that would clip, so they stay at the same level as one another.
    public static let gain: Float = 1.5
    public static let ceiling: Float = 0.95

    /// A 16-bit mono WAV file of `samples`.
    public static func wav(_ samples: [Float], sampleRate: Int = KokoroModel.sampleRate) -> Data {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let scale = peak > 0 ? min(gain, ceiling / peak) : 1
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        let bytes = samples.count * 2
        put("RIFF"); put(UInt32(36 + bytes)); put("WAVE")
        put("fmt "); put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(sampleRate)); put(UInt32(sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
        put("data"); put(UInt32(bytes))
        for sample in samples { put(Int16((max(-1, min(1, sample * scale)) * 32767).rounded())) }
        return data
    }
}
