import CryptoKit
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct LocalVoiceTests {
    @Test func theModelIsOneDownloadFixedToARevisionAndEveryFileHasAHash() throws {
        #expect(KokoroModel.files.count == 1 + KokoroModel.voices.count)
        #expect(KokoroModel.files.allSatisfy { $0.sha256.count == 64 && $0.sha256.allSatisfy(\.isHexDigit) && $0.size > 0 })
        #expect(Set(KokoroModel.voices.map(\.id)).count == KokoroModel.voices.count)
        let url = try #require(KokoroModel.url(for: KokoroModel.weights))
        #expect(url.absoluteString == "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/\(KokoroModel.revision)/kokoro-v1_0.safetensors")
        #expect(KokoroModel.revision.count == 40)
        // Only a known file can be asked for.
        #expect(KokoroModel.url(for: KokoroModel.File(path: "../../elsewhere", size: 1, sha256: "x")) == nil)
        #expect(KokoroModel.totalBytes > 327_000_000 && KokoroModel.totalBytes < 340_000_000)
    }

    @Test func aVoiceIsFoundByNameOrIDAndKnowsItsAccent() throws {
        #expect(KokoroModel.voice(named: " heart ")?.id == "af_heart")
        #expect(KokoroModel.voice(named: "BM_GEORGE")?.name == "George")
        #expect(KokoroModel.voice(named: "Nobody") == nil && KokoroModel.voice(named: nil) == nil && KokoroModel.voice(named: "") == nil)
        #expect(try #require(KokoroModel.voice(id: "bf_emma")).isBritish)
        #expect(try #require(KokoroModel.voice(id: "af_heart")).title == "Heart · American")
        #expect(KokoroModel.voice(id: KokoroModel.defaultVoice) != nil)
    }

    @Test func missingFilesAreThoseAbsentOrTheWrongSize() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kokoro-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(KokoroModel.missing(in: folder).count == KokoroModel.files.count)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("voices"), withIntermediateDirectories: true)
        let voice = try #require(KokoroModel.voices.first)
        try Data(count: voice.file.size).write(to: folder.appendingPathComponent(voice.file.path))
        #expect(!KokoroModel.missing(in: folder).contains(voice.file))
        try Data(count: 10).write(to: folder.appendingPathComponent(voice.file.path))  // truncated
        #expect(KokoroModel.missing(in: folder).contains(voice.file))
    }

    @Test func theHashOfAFileIsTheRealOne() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data((0..<3_000_000).map { UInt8($0 % 251) })  // more than one read
        try data.write(to: file)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(try KokoroModel.sha256(of: file) == expected)
        #expect(throws: (any Error).self) { try KokoroModel.sha256(of: file.appendingPathExtension("missing")) }
    }

    @Test func textIsSplitIntoPiecesTheModelCanTake() {
        #expect(LocalSpeech.chunks(of: "  ").isEmpty)
        #expect(LocalSpeech.chunks(of: "Open the app.") == ["Open the app."])
        // Short sentences are packed together, in order.
        #expect(LocalSpeech.chunks(of: "One. Two! Three?") == ["One. Two! Three?"])
        let sentences = (1...12).map { "This is sentence number \($0) of the line." }
        let packed = LocalSpeech.chunks(of: sentences.joined(separator: " "), maxCharacters: 100)
        #expect(packed.count > 1 && packed.allSatisfy { $0.count <= 100 })
        #expect(packed.joined(separator: " ") == sentences.joined(separator: " "))
        // A sentence that is too long is broken near a pause, and nothing is lost.
        let long = "First we open the library, then we pick the take we want to edit, and after that we choose the Studio tab to begin"
        let pieces = LocalSpeech.chunks(of: long, maxCharacters: 60)
        #expect(pieces.count >= 2 && pieces.allSatisfy { $0.count <= 60 })
        #expect(pieces.joined(separator: " ") == long)
        // One enormous word is cut where it must be.
        let word = String(repeating: "a", count: 450)
        let cut = LocalSpeech.chunks(of: word, maxCharacters: 200)
        #expect(cut.map(\.count) == [200, 200, 50])
    }

    @Test func piecesOfAudioAreJoinedWithASilenceBetweenThem() {
        let joined = LocalSpeech.joined([[1, 1], [2], [3]], sampleRate: 100, gap: 0.1)
        #expect(joined == [1, 1] + [Float](repeating: 0, count: 10) + [2] + [Float](repeating: 0, count: 10) + [3])
        #expect(LocalSpeech.joined([]).isEmpty)
    }

    @Test func aWavFileHasTheRightHeaderLengthAndLoudness() throws {
        let quiet: [Float] = [0, 0.2, -0.2, 0.1]
        let data = LocalSpeech.wav(quiet, sampleRate: 24_000)
        #expect(data.count == 44 + quiet.count * 2)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF" && String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        func word(_ at: Int) -> UInt32 { data[at..<at + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian }
        #expect(word(4) == UInt32(data.count - 8) && word(24) == 24_000 && word(40) == UInt32(quiet.count * 2))
        func sample(_ index: Int) -> Int16 { data[44 + index * 2..<46 + index * 2].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }.littleEndian }
        // Quiet audio is raised by the fixed gain; loud audio is held under the ceiling instead of clipping.
        #expect(abs(Double(sample(1)) - 0.3 * 32767) < 2)
        let loud = LocalSpeech.wav([0.9, -0.5], sampleRate: 24_000)
        let peak = loud[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }.littleEndian
        #expect(Double(peak) <= Double(LocalSpeech.ceiling) * 32767 + 1 && peak > 0)
        #expect(LocalSpeech.wav([]).count == 44)
        #expect(LocalSpeech.wav([0, 0]).count == 48)  // silence stays silence
    }

    @Test func aFasterEngineMayBeAskedForMoreSpeedThanTheDefault() {
        #expect(VoiceoverPlan.speed(for: 6, room: 4, maximum: 1.3) == 1.3)
        #expect(VoiceoverPlan.speed(for: 6, room: 4) == 1.2)
        #expect(VoiceoverPlan.speed(for: 4.4, room: 4, maximum: 1.3)! < 1.2)
    }
}
