import CoreGraphics
import Foundation
import Testing

@testable import RelaytakeCore

@Suite struct SensitiveTextTests {
    private func kinds(_ line: String, terms: [String] = []) -> [SensitiveKind] {
        SensitiveText.matches(in: line, terms: terms).map(\.kind)
    }

    @Test func findsEmailAddressesAndKeys() {
        let matches = SensitiveText.matches(in: "Mail jo.smith+demo@example.com with sk-ant-api03-abcdefGHIJKLmnop1234567890")
        #expect(matches.map(\.kind) == [.email, .secret])
        #expect(matches[0].text == "jo.smith+demo@example.com")
        #expect(matches[1].text.hasPrefix("sk-ant-"))
        #expect(kinds("AKIAIOSFODNN7EXAMPLE") == [.secret])
        #expect(kinds("ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789") == [.secret])
    }

    @Test func aLabeledPasswordHidesOnlyTheValue() {
        let matches = SensitiveText.matches(in: "password: hunter22!")
        #expect(matches.count == 1)
        #expect(matches.first?.text == "hunter22!")
    }

    @Test func cardNumbersMustPassTheCheckDigit() {
        #expect(kinds("Card 4242 4242 4242 4242 exp 12/30") == [.card])
        #expect(!kinds("Order 4242 4242 4242 4241").contains(.card))
    }

    @Test func findsIDAndPhoneNumbers() {
        #expect(kinds("SSN 123-45-6789") == [.idNumber])
        // Not a valid ID number (it may still be taken for a phone number, which is the safe side).
        #expect(!kinds("SSN 000-45-6789").contains(.idNumber))
        #expect(kinds("Call (415) 555-0132 today").contains(.phone))
    }

    @Test func ordinaryTextIsLeftAlone() {
        #expect(kinds("Sources/RelaytakeCore/StudioAnnotations.swift").isEmpty)
        #expect(kinds("commit 58a7122f0c1d2e3b4a5968778695a4b3c2d1e0f9").isEmpty)
        #expect(kinds("The meeting is at 3:30 on 2026-10-28").isEmpty)
    }

    @Test func blursTheWordsThePersonListsInAnyCase() {
        let terms = SensitiveText.terms(from: "Acme Corp, darin\n , x")
        #expect(terms == ["Acme Corp", "darin"])
        let matches = SensitiveText.matches(in: "Darin at ACME CORP and darin again", terms: terms)
        #expect(matches.map(\.text) == ["Darin", "ACME CORP", "darin"])
    }

    @Test func maskingNeverShowsTheWholeText() {
        let masked = SensitiveText.masked("sk-ant-abcdefghijklmnop")
        #expect(masked.hasPrefix("sk-") && masked.contains("•"))
        #expect(!masked.contains("ghijk"))
        #expect(SensitiveText.masked("abc") == "•••")
    }
}

@Suite struct SensitiveFindingTests {
    private let rect = CGRect(x: 0.2, y: 0.3, width: 0.2, height: 0.03)

    private func seen(_ times: [Double], text: String = "a@b.co", at rect: CGRect? = nil) -> [SensitiveSighting] {
        times.map { SensitiveSighting(kind: .email, text: text, time: $0, rect: rect ?? self.rect) }
    }

    @Test func sightingsInARowBecomeOneStretchWithASampleEitherSide() {
        let findings = SensitiveScan.findings(from: seen([2, 2.5, 3, 3.5]), duration: 10)
        #expect(findings.count == 1)
        #expect(findings[0].start == 1.5 && findings[0].end == 4)
        // Padded around the letters.
        #expect(findings[0].rect.contains(rect))
        #expect(findings[0].rect.height > rect.height)
    }

    @Test func aGapStartsANewStretch() {
        let findings = SensitiveScan.findings(from: seen([1, 1.5, 5, 5.5]), duration: 10)
        #expect(findings.count == 2)
    }

    @Test func stretchesStayInsideTheRecording() {
        let findings = SensitiveScan.findings(from: seen([0, 9.8]), duration: 10)
        #expect(findings.allSatisfy { $0.start >= 0 && $0.end <= 10 })
    }

    @Test func textThatScrollsALittleIsFollowedAndCovered() {
        var sightings = seen([1], at: rect)
        sightings += seen([1.5], at: rect.offsetBy(dx: 0, dy: -0.02))
        let findings = SensitiveScan.findings(from: sightings, duration: 10)
        #expect(findings.count == 1)
        #expect(findings[0].rect.contains(rect) && findings[0].rect.contains(rect.offsetBy(dx: 0, dy: -0.02)))
    }

    @Test func textThatScrollsALongWaySplitsWithoutAnUncoveredMoment() {
        let path = (0..<6).map { step in rect.offsetBy(dx: 0, dy: -0.04 * Double(step)) }
        let sightings = path.enumerated().flatMap { step, place in seen([1 + 0.5 * Double(step)], at: place) }
        let findings = SensitiveScan.findings(from: sightings, duration: 10).sorted { $0.start < $1.start }
        #expect(findings.count > 1)
        for (a, b) in zip(findings, findings.dropFirst()) { #expect(b.start <= a.end) }
        for place in path { #expect(findings.contains { $0.rect.contains(place) }) }
    }

    @Test func twoCopiesOnScreenAtOnceStaySeparate() {
        let other = rect.offsetBy(dx: 0, dy: 0.5)
        let sightings = seen([1, 1.5], at: rect) + seen([1, 1.5], at: other)
        let findings = SensitiveScan.findings(from: sightings, duration: 10)
        #expect(findings.count == 2)
    }

    @Test func blursFollowTheCutsAndSkipWhatWasCutOut() throws {
        var cuts = EditModel(duration: 20)
        try cuts.remove(TimeSpan(start: 4, end: 6))
        let finding = SensitiveFinding(kind: .email, text: "a@b.co", start: 3, end: 7, rect: rect)
        let blurs = SensitiveScan.blurs(for: finding, cuts: cuts)
        // 3–4 and 6–7 survive; in the edited video they are 3–4 and 4–5.
        #expect(blurs.count == 2)
        #expect(blurs.map(\.start) == [3, 4] && blurs.map(\.end) == [4, 5])
        #expect(blurs.allSatisfy { $0.kind == .blur && abs($0.rect.minX - rect.minX) < 1e-9 && abs($0.rect.maxY - rect.maxY) < 1e-9 })

        let gone = SensitiveFinding(kind: .email, text: "a@b.co", start: 4.2, end: 5.8, rect: rect)
        #expect(SensitiveScan.blurs(for: gone, cuts: cuts).isEmpty)
    }

    @Test func aBriefSightingStillMakesAUsableMark() {
        let finding = SensitiveFinding(kind: .secret, text: "x", start: 9.9, end: 10, rect: rect)
        let blurs = SensitiveScan.blurs(for: finding, cuts: EditModel(duration: 10))
        #expect(blurs.count == 1)
        #expect(blurs[0].length >= ShapeOverlay.minimumLength - 1e-9 && blurs[0].end <= 10)
    }
}
