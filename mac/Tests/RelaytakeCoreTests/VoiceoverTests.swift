import Foundation
import Testing

@testable import RelaytakeCore

/// A transport that answers from a script and remembers what it was asked. Nothing here touches a network.
private final class ScriptedTransport: ElevenLabsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Data, Int)]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [(Data, Int)]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        lock.withLock {
            requests.append(request)
            return replies.isEmpty ? (Data(), 500) : replies.removeFirst()
        }
    }
}

/// An engine that "speaks" by returning bytes whose length stands for how long the line takes.
private final class FakeEngine: SpeechEngine, @unchecked Sendable {
    let fileExtension = "mp3"
    let supportsSpeed: Bool
    private let lock = NSLock()
    private(set) var calls: [(text: String, speed: Double, previous: String?, next: String?)] = []
    private let script: @Sendable (String, Double, Int) throws -> Data

    init(supportsSpeed: Bool = true, script: @escaping @Sendable (String, Double, Int) throws -> Data) {
        self.supportsSpeed = supportsSpeed; self.script = script
    }

    func speak(text: String, speed: Double, previous: String?, next: String?) async throws -> Data {
        let count = lock.withLock {
            calls.append((text, speed, previous, next))
            return calls.count
        }
        return try script(text, speed, count)
    }
}

private func audio(seconds: Double) -> Data {
    // 1 byte per millisecond is enough for the stub's `measure`.
    Data(repeating: 7, count: Int(seconds * 1000))
}

private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("voiceover-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let measureByBytes: @Sendable (URL) async -> Double? = { url in
    (try? Data(contentsOf: url)).map { Double($0.count) / 1000 }
}

@Suite struct ElevenLabsRequestTests {
    @Test func aKeyIsOneRunOfPrintableCharactersAndNothingElse() {
        #expect(ElevenLabs.cleaned(key: "  sk_abcdef123456\n") == "sk_abcdef123456")
        #expect(ElevenLabs.cleaned(key: "short") == nil)
        #expect(ElevenLabs.cleaned(key: "has a space inside") == nil)
        #expect(ElevenLabs.cleaned(key: "sk_abc\r\nX-Evil: 1") == nil)
        #expect(ElevenLabs.cleaned(key: "sk_ключ_abcdef") == nil)
        #expect(ElevenLabs.cleaned(key: String(repeating: "a", count: 300)) == nil)
    }

    @Test func aVoiceIDCannotChangeWhichAddressIsAsked() {
        #expect(ElevenLabs.isSafeVoiceID("21m00Tcm4TlvDq8ikWAM"))
        #expect(ElevenLabs.isSafeVoiceID("a-b_c"))
        #expect(!ElevenLabs.isSafeVoiceID("../v1/user"))
        #expect(!ElevenLabs.isSafeVoiceID("abc/def"))
        #expect(!ElevenLabs.isSafeVoiceID("abc?x=1"))
        #expect(!ElevenLabs.isSafeVoiceID(""))
        #expect(ElevenLabs.speechRequest(text: "Hi", voiceID: "../x", model: .multilingualV2, key: "sk_abcdef123456") == nil)
    }

    @Test func everyRequestGoesToElevenLabsOverHTTPSWithTheKeyInTheHeaderOnly() throws {
        let key = "sk_abcdef123456"
        let requests = [
            ElevenLabs.voicesRequest(key: key), ElevenLabs.voicesRequest(key: key, pageToken: "next page"),
            ElevenLabs.subscriptionRequest(key: key),
            try #require(ElevenLabs.speechRequest(text: "Hello", voiceID: "abc123", model: .flashV2_5, speed: 1.1, key: key)),
        ]
        for request in requests {
            let url = try #require(request.url)
            #expect(url.scheme == "https" && url.host == ElevenLabs.host)
            #expect(request.value(forHTTPHeaderField: "xi-api-key") == key)
            #expect(!url.absoluteString.contains(key))
        }
        #expect(requests[1].url?.query?.contains("next_page_token=next%20page") == true)
    }

    @Test func speechCarriesTheTextModelAndOnlyTheSpeedItIsAskedFor() throws {
        func body(_ request: URLRequest?) throws -> [String: Any] {
            let data = try #require(request?.httpBody)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let normal = try body(ElevenLabs.speechRequest(
            text: "Open the app.", voiceID: "abc", model: .multilingualV2, previousText: "Before.", nextText: "After.", key: "sk_abcdef123456"))
        #expect(normal["text"] as? String == "Open the app.")
        #expect(normal["model_id"] as? String == "eleven_multilingual_v2")
        #expect(normal["previous_text"] as? String == "Before." && normal["next_text"] as? String == "After.")
        #expect(normal["voice_settings"] == nil)  // the voice keeps the settings saved in the account

        let fast = try body(ElevenLabs.speechRequest(text: "x", voiceID: "abc", model: .flashV2_5, speed: 5, key: "sk_abcdef123456"))
        let settings = try #require(fast["voice_settings"] as? [String: Double])
        #expect(settings["speed"] == 1.2)  // never past what the service allows
    }

    @Test func voicesAndSubscriptionAreReadFromTheServicesReplies() throws {
        let voices = Data("""
        {"voices":[{"voice_id":"abc","name":"Rachel","category":"premade"},{"voice_id":"../bad","name":"Nope"},{"name":"No id"}],
         "has_more":true,"next_page_token":"tok"}
        """.utf8)
        let page = try #require(ElevenLabs.parseVoices(voices))
        #expect(page.voices == [ElevenLabs.Voice(id: "abc", name: "Rachel", category: "premade")])
        #expect(page.next == "tok")
        #expect(ElevenLabs.parseVoices(Data("[]".utf8)) == nil)

        let plan = try #require(ElevenLabs.parseSubscription(Data(
            #"{"tier":"starter","character_count":1200,"character_limit":30000,"next_character_count_reset_unix":1800000000}"#.utf8)))
        #expect(plan.used == 1200 && plan.limit == 30000 && plan.remaining == 28800)
        #expect(plan.resets == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(ElevenLabs.parseSubscription(Data("{}".utf8)) == nil)
    }

    @Test func failuresSayWhatToDo() {
        func failure(_ status: Int, _ json: String) -> ElevenLabs.Failure { ElevenLabs.failure(status: status, body: Data(json.utf8)) }
        #expect(failure(401, #"{"detail":{"status":"invalid_api_key","message":"x"}}"#) == .invalidKey)
        #expect(failure(401, #"{"detail":{"status":"quota_exceeded","message":"x"}}"#) == .outOfCharacters)
        #expect(failure(401, #"{"detail":{"status":"missing_permissions","message":"The API key you used is missing the permission text_to_speech to execute this operation."}}"#)
            == .missingPermission("Text to speech"))
        #expect(failure(404, "{}") == .voiceNotFound)
        #expect(failure(429, "{}") == .rateLimited)
        #expect(failure(422, #"{"detail":[{"msg":"text is empty"}]}"#) == .rejected("text is empty"))
        #expect(failure(503, "") == .server(503))
        #expect(failure(401, "").errorDescription?.contains("did not accept") == true)
    }

    @Test func signingInChecksTheKeyBeforeKeepingItAndAcceptsAKeyThatCannotReadThePlan() async throws {
        let voices = Data(#"{"voices":[{"voice_id":"abc","name":"Rachel"}],"has_more":false}"#.utf8)
        let limited = ElevenLabsService(transport: ScriptedTransport([
            (voices, 200),
            (Data(#"{"detail":{"status":"missing_permissions","message":"missing the permission user_read"}}"#.utf8), 401),
        ]))
        let signedIn = try await limited.signIn(key: " sk_abcdef123456 ")
        #expect(signedIn.key == "sk_abcdef123456")
        #expect(signedIn.voices.map(\.name) == ["Rachel"])
        #expect(signedIn.subscription == nil)

        let rejecting = ElevenLabsService(transport: ScriptedTransport([(Data(#"{"detail":{"status":"invalid_api_key"}}"#.utf8), 401)]))
        await #expect(throws: ElevenLabs.Failure.invalidKey) { try await rejecting.signIn(key: "sk_abcdef123456") }
        // A key with spaces never leaves the Mac.
        let neverAsked = ScriptedTransport([])
        await #expect(throws: ElevenLabs.Failure.invalidKey) {
            try await ElevenLabsService(transport: neverAsked).signIn(key: "not a key at all")
        }
        #expect(neverAsked.requests.isEmpty)
    }
}

@Suite struct VoiceoverPlanTests {
    @Test func narrationBeatsBecomeLinesThatMayTakeTheRestOfTheirPart() {
        let beats = [
            NarrationBeat(name: "Open", start: 0, end: 10, text: "  Open   the app. "),
            NarrationBeat(name: "Wait", start: 10, end: 14, text: nil),
            NarrationBeat(name: "Blink", start: 14, end: 14.2, text: "Too short a part."),
            NarrationBeat(name: "Show", start: 14.2, end: 20, text: "Here it is."),
        ]
        let lines = VoiceoverPlan.lines(beats: beats)
        #expect(lines.map(\.name) == ["Open", "Show"])
        #expect(lines[0].text == "Open the app.")
        #expect(abs(lines[0].start - 0.1) < 1e-9)
        #expect(abs(lines[0].room - (10 - 0.1 - VoiceoverPlan.gap)) < 1e-9)
        #expect(VoiceoverPlan.characters(lines) == "Open the app.".count + "Here it is.".count)
    }

    @Test func aTranscriptMovesOntoTheEditedVideoAndACutLineIsDropped() {
        // 0–30 s recording with 10–20 s cut out.
        let cuts = EditModel(duration: 30, segments: [TimeSpan(start: 0, end: 10), TimeSpan(start: 20, end: 30)])
        let transcript = [
            CaptionSegment(start: 22, end: 25, text: "After the cut."),
            CaptionSegment(start: 1, end: 4, text: "Before the cut."),
            CaptionSegment(start: 12, end: 15, text: "Inside the cut."),
            CaptionSegment(start: 26, end: 27, text: "   "),
        ]
        let lines = VoiceoverPlan.lines(transcript: transcript, cuts: cuts, outputDuration: 20)
        #expect(lines.map(\.text) == ["Before the cut.", "After the cut."])
        #expect(lines[0].start == 1)
        #expect(abs(lines[0].room - (12 - 1 - VoiceoverPlan.gap)) < 1e-9)  // may run until the next line begins (22 s → 12 s edited)
        #expect(abs(lines[1].room - (20 - 12 - VoiceoverPlan.gap)) < 1e-9)  // the last runs to the end of the video
    }

    @Test func aLongLineIsSpedUpJustEnoughAndNeverPastTheLimit() {
        #expect(VoiceoverPlan.speed(for: 4, room: 5) == nil)
        #expect(VoiceoverPlan.speed(for: 5.04, room: 5) == nil)
        let fitted = VoiceoverPlan.speed(for: 5.5, room: 5)
        #expect(fitted != nil && fitted! > 1.1 && fitted! <= 1.2)
        #expect(VoiceoverPlan.speed(for: 20, room: 5) == 1.2)
    }
}

@Suite struct VoiceoverGenerationTests {
    private func lines(_ rooms: [Double]) -> [VoiceLine] {
        var start = 0.0
        return rooms.enumerated().map { index, room in
            defer { start += room + 1 }
            return VoiceLine(name: "Step \(index + 1)", text: "Line number \(index + 1).", start: start, room: room)
        }
    }

    @Test func eachLineIsSpokenWrittenAndMeasuredWithItsNeighboursForContext() async throws {
        let engine = FakeEngine { _, _, _ in audio(seconds: 2) }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await VoiceoverPlan.generate(
            lines: lines([5, 5, 5]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        #expect(result.spoken.count == 3 && result.stopped == nil && result.skipped.isEmpty)
        #expect(result.spoken.allSatisfy { abs($0.duration - 2) < 0.01 && !$0.overran && $0.speed == 1 })
        #expect(result.charactersSent == lines([5, 5, 5]).reduce(0) { $0 + $1.text.count })
        #expect(engine.calls[0].previous == nil && engine.calls[0].next == "Line number 2.")
        #expect(engine.calls[1].previous == "Line number 1." && engine.calls[1].next == "Line number 3.")
        #expect(engine.calls[2].next == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("1.mp3").path))
    }

    @Test func aLineThatRunsLongIsSpokenAgainFasterAndShortenedByTheSpeed() async throws {
        let engine = FakeEngine { _, speed, _ in audio(seconds: 6 / speed) }  // 6 s at normal speed
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await VoiceoverPlan.generate(
            lines: lines([5.4]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        #expect(engine.calls.count == 2 && engine.calls[0].speed == 1 && engine.calls[1].speed > 1.1)
        let spoken = try #require(result.spoken.first)
        #expect(spoken.duration <= 5.4 + 0.05 && !spoken.overran)
        // Both attempts are billed.
        #expect(result.charactersSent == 2 * lines([5.4])[0].text.count)
    }

    @Test func aLineThatCannotFitIsReportedAndCutAtItsRoom() async throws {
        let engine = FakeEngine { _, speed, _ in audio(seconds: 12 / speed) }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await VoiceoverPlan.generate(
            lines: lines([5]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        let spoken = try #require(result.spoken.first)
        #expect(spoken.overran && spoken.speed == 1.2)
        #expect(VoiceoverPlan.warnings(for: result).contains { $0.contains("Step 1") && $0.contains("cut off") })

        var project = StudioProject(duration: 30)
        VoiceoverPlan.place(result.spoken, in: &project, replacingOriginalAudio: false)
        let clip = try #require(project.clips.first)
        #expect(abs(clip.length - 5) < 1e-9 && clip.fadeOut > 0)
    }

    @Test func anEngineWithoutSpeedIsNotAskedAgain() async throws {
        let engine = FakeEngine(supportsSpeed: false) { _, _, _ in audio(seconds: 9) }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await VoiceoverPlan.generate(
            lines: lines([5]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        #expect(engine.calls.count == 1 && result.spoken.first?.overran == true)
    }

    @Test func aRefusedLineIsSkippedAndTheRestGoOn() async throws {
        let engine = FakeEngine { text, _, _ in
            if text.contains("2") { throw SpeechFailure.lineRefused("text is empty") }
            return audio(seconds: 1)
        }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await VoiceoverPlan.generate(
            lines: lines([5, 5, 5]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        #expect(result.spoken.count == 2 && result.stopped == nil)
        #expect(result.skipped == ["“Step 2” was refused: text is empty"])
    }

    @Test func aProblemThatWouldRepeatStopsTheRunButKeepsWhatWasSpoken() async throws {
        let engine = FakeEngine { _, _, count in
            if count == 2 { throw SpeechFailure.stop("Your ElevenLabs plan has no characters left this period.") }
            return audio(seconds: 1)
        }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let result = try await VoiceoverPlan.generate(
            lines: lines([5, 5, 5]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        #expect(result.spoken.count == 1 && engine.calls.count == 2)
        #expect(VoiceoverPlan.warnings(for: result) == ["Voiceover stopped after 1 line: Your ElevenLabs plan has no characters left this period."])
    }

    @Test func aBusyServiceIsRetriedThenGivenUpOn() async throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recovering = FakeEngine { _, _, count in
            if count == 1 { throw SpeechFailure.busy }
            return audio(seconds: 1)
        }
        let ok = try await VoiceoverPlan.generate(
            lines: lines([5]), engine: recovering, retryDelay: 0, destination: { folder.appendingPathComponent("a\($0).mp3") }, measure: measureByBytes)
        #expect(ok.spoken.count == 1 && recovering.calls.count == 2)

        let stuck = FakeEngine { _, _, _ in throw SpeechFailure.busy }
        let failed = try await VoiceoverPlan.generate(
            lines: lines([5]), engine: stuck, retryDelay: 0, destination: { folder.appendingPathComponent("b\($0).mp3") }, measure: measureByBytes)
        #expect(failed.spoken.isEmpty && failed.stopped != nil && stuck.calls.count == 3)
    }

    @Test func aVeryLongLineIsNotSentAtAll() async throws {
        let engine = FakeEngine { _, _, _ in audio(seconds: 1) }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let long = VoiceLine(name: "Essay", text: String(repeating: "word ", count: 600), start: 0, room: 60)
        let result = try await VoiceoverPlan.generate(
            lines: [long], engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        #expect(engine.calls.isEmpty && result.skipped.count == 1 && result.charactersSent == 0)
    }

    @Test func cancellingStopsBeforeAnotherLineIsSent() async throws {
        let engine = FakeEngine { _, _, _ in audio(seconds: 1) }
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let task = Task {
            try await VoiceoverPlan.generate(
                lines: lines([5, 5]), engine: engine, destination: { folder.appendingPathComponent("\($0).mp3") }, measure: measureByBytes)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(engine.calls.isEmpty)
    }

    @Test func spokenLinesLandOnTheVoiceoverTrackAndASecondRunReplacesTheFirst() throws {
        func spoken(_ start: Double, _ duration: Double) -> VoiceoverPlan.Spoken {
            VoiceoverPlan.Spoken(
                line: VoiceLine(name: "x", text: "x", start: start, room: 5), url: URL(fileURLWithPath: "/tmp/\(start).mp3"),
                duration: duration, speed: 1, overran: false)
        }
        var project = StudioProject(duration: 30)
        let mine = project.addVoiceover(url: URL(fileURLWithPath: "/tmp/mine.m4a"), name: "Voiceover", fileDuration: 2, start: 25)
        VoiceoverPlan.place([spoken(8, 3), spoken(2, 4)], in: &project, replacingOriginalAudio: true)
        let voices = project.clips.filter { $0.name == ElevenLabs.clipName }
        #expect(voices.map(\.start).sorted() == [2, 8] && voices.allSatisfy { $0.kind == .voiceover })
        #expect(project.originalVolume == 0)
        #expect(project.clips.contains { $0.id == mine })  // a person's own recording is not touched

        VoiceoverPlan.place([spoken(4, 2)], in: &project, replacingOriginalAudio: false)
        #expect(project.clips.filter { $0.name == ElevenLabs.clipName }.map(\.start) == [4])
        #expect(project.clips.contains { $0.id == mine })
    }

    @Test func theNextFreeAudioNumberSkipsFilesAlreadyThere() throws {
        let folder = scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = TakeFiles(directory: folder, baseName: "Take")
        #expect(VoiceoverPlan.freeAudioNumber(in: files) == 1)
        try FileManager.default.createDirectory(at: files.audioDirectory, withIntermediateDirectories: true)
        try Data([1]).write(to: files.audioFile(number: 1, extension: "mp3"))
        try Data([1]).write(to: files.audioFile(number: 2, extension: "m4a"))
        #expect(VoiceoverPlan.freeAudioNumber(in: files) == 3)
    }

    @Test func theElevenLabsEngineSortsServiceFailuresIntoWhatEachMeansForTheRun() async throws {
        func engine(_ status: Int, _ body: String) -> ElevenLabsEngine {
            ElevenLabsEngine(
                service: ElevenLabsService(transport: ScriptedTransport([(Data(body.utf8), status)])), key: "sk_abcdef123456",
                voiceID: "abc", model: .multilingualV2)
        }
        await #expect(throws: SpeechFailure.busy) { try await engine(429, "{}").speak(text: "x", speed: 1, previous: nil, next: nil) }
        await #expect(throws: SpeechFailure.lineRefused("text is empty")) {
            try await engine(422, #"{"detail":"text is empty"}"#).speak(text: "x", speed: 1, previous: nil, next: nil)
        }
        do {
            _ = try await engine(401, #"{"detail":{"status":"quota_exceeded"}}"#).speak(text: "x", speed: 1, previous: nil, next: nil)
            Issue.record("expected a stop")
        } catch SpeechFailure.stop(let why) {
            #expect(why.contains("no characters left"))
        }
        // Audio that is far too small to be speech is treated as unreadable, not saved.
        await #expect(throws: SpeechFailure.stop(ElevenLabs.Failure.unreadable.localizedDescription)) {
            try await engine(200, "tiny").speak(text: "x", speed: 1, previous: nil, next: nil)
        }
    }
}

@Suite struct VoiceoverEditListTests {
    @Test func anAgentsEditListCanAskForAVoiceAndOlderListsStillDecode() throws {
        let asked = try JSONDecoder().decode(
            EditList.self, from: Data(#"{"narration":{"Open":"Open it."},"voiceover":{"voice":"Rachel","keepOriginalAudio":true}}"#.utf8))
        #expect(asked.voiceover == EditList.Voiceover(voice: "Rachel", keepOriginalAudio: true))
        let plain = try JSONDecoder().decode(EditList.self, from: Data(#"{"narration":{"Open":"Open it."}}"#.utf8))
        #expect(plain.voiceover == nil)
        // A voiceover on its own is not an edit that changes the picture, so it adds nothing to a list that otherwise does nothing.
        let (project, _) = EditListApplier.apply(EditList(voiceover: .init()), to: StudioProject(duration: 30), markers: [], clicks: [])
        #expect(!project.isEdited)
    }
}

@Suite struct VoiceoverFromAnEditTests {
    @Test func anEditsNarrationBecomesLinesSpokenInTheirPartsOnTheVoiceoverTrack() async throws {
        let markers = [AgentMarker(name: "Open", time: 0), AgentMarker(name: "Wait", time: 10), AgentMarker(name: "Show", time: 20)]
        let list = EditList(
            cuts: [.init(from: .marker("Wait"), to: .marker("Show"))],
            narration: ["Open": "Open the app.", "Show": "Here is the result.", "Wait": "This part is cut."],
            voiceover: .init(voice: "Heart", engine: "local"))
        let (project, outcome) = EditListApplier.apply(list, to: StudioProject(duration: 40), markers: markers, clicks: [])
        let lines = VoiceoverPlan.lines(beats: outcome.beats)
        // The cut part has no room, so it is not spoken; the others begin inside their parts on the edited video.
        #expect(lines.map(\.name) == ["Open", "Show"])
        #expect(abs(lines[0].start - 0.1) < 1e-9 && abs(lines[1].start - 10.1) < 1e-9)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("edit-voice-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let engine = FakeEngine { _, _, _ in audio(seconds: 2) }
        let result = try await VoiceoverPlan.generate(
            lines: lines, engine: engine, destination: { folder.appendingPathComponent("\($0).wav") }, measure: measureByBytes)
        var edited = project
        VoiceoverPlan.place(result.spoken, in: &edited, replacingOriginalAudio: true)
        #expect(edited.clips.map(\.start).sorted() == [lines[0].start, lines[1].start])
        #expect(edited.originalVolume == 0)
        #expect(edited.cuts == project.cuts)  // speaking never changes the picture
    }

    @Test func theEngineNamesAnEditMayUseAreTheOnesTheAppUnderstands() {
        #expect(EditList.Voiceover(voice: "Emma", engine: "local").engine == "local")
        let decoded = try? JSONDecoder().decode(EditList.self, from: Data(#"{"voiceover":{"engine":"elevenlabs","voice":"Rachel"}}"#.utf8))
        #expect(decoded?.voiceover == EditList.Voiceover(voice: "Rachel", engine: "elevenlabs"))
    }
}
