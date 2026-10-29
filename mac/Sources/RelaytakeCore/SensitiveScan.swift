import CoreGraphics
import Foundation

// Finding sensitive text on screen so it can be blurred: email addresses, phone numbers, card numbers, keys
// and tokens, and words the person lists. The app reads the text off sampled frames on this Mac; the rules
// here decide which of it is sensitive, join sightings across frames into stretches, and turn those into
// ordinary blur marks on the edited timeline. Detection is a helper, not a guarantee: small, blurry or
// briefly shown text can be missed, so every finding is reviewed before it becomes a blur.

public enum SensitiveKind: String, Codable, CaseIterable, Sendable {
    case secret, card, idNumber, email, phone, address, custom

    public var title: String {
        switch self {
        case .secret: "Key or password"
        case .card: "Card number"
        case .idNumber: "ID number"
        case .email: "Email address"
        case .phone: "Phone number"
        case .address: "Street address"
        case .custom: "Your word"
        }
    }
}

/// One piece of sensitive text inside a line of recognized text.
public struct SensitiveMatch: Equatable, Sendable {
    public var kind: SensitiveKind
    public var range: Range<String.Index>
    public var text: String
}

public enum SensitiveText {
    /// The sensitive pieces of `line`, in order, never overlapping. When two rules claim the same text the
    /// stronger kind (a key before a phone number, say) wins.
    public static func matches(in line: String, terms: [String] = []) -> [SensitiveMatch] {
        var found: [SensitiveMatch] = []
        func add(_ kind: SensitiveKind, _ range: Range<String.Index>) {
            guard !range.isEmpty, !found.contains(where: { $0.range.overlaps(range) }) else { return }
            found.append(SensitiveMatch(kind: kind, range: range, text: String(line[range])))
        }

        for pattern in secretPatterns { for range in ranges(of: pattern, in: line) { add(.secret, range) } }
        for range in ranges(of: labeledSecret, in: line, group: 1) { add(.secret, range) }
        for range in ranges(of: longToken, in: line) where looksRandom(String(line[range])) { add(.secret, range) }
        for range in ranges(of: cardNumber, in: line) where passesLuhn(String(line[range])) { add(.card, range) }
        for range in ranges(of: socialSecurity, in: line) { add(.idNumber, range) }
        for range in ranges(of: email, in: line) { add(.email, range) }
        if let detector {
            let whole = NSRange(line.startIndex..., in: line)
            for result in detector.matches(in: line, range: whole) {
                guard let range = Range(result.range, in: line) else { continue }
                switch result.resultType {
                case .phoneNumber where line[range].filter(\.isNumber).count >= 7: add(.phone, range)
                case .address: add(.address, range)
                default: break
                }
            }
        }
        for term in cleaned(terms) {
            var from = line.startIndex
            while let range = line.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: from..<line.endIndex) {
                add(.custom, range)
                from = range.upperBound
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The person's list of words to blur, as typed: split on commas and new lines, trimmed, too-short ones dropped.
    public static func terms(from typed: String) -> [String] {
        cleaned(typed.components(separatedBy: CharacterSet(charactersIn: ",\n")))
    }

    /// The text with most of it hidden, for listing a finding without showing the secret again: "jo••••••om".
    public static func masked(_ text: String) -> String {
        let characters = Array(text.trimmingCharacters(in: .whitespaces))
        guard characters.count > 6 else { return String(repeating: "•", count: max(3, characters.count)) }
        let shown = min(3, characters.count / 5)
        return String(characters.prefix(shown)) + String(repeating: "•", count: min(12, characters.count - 2 * shown))
            + String(characters.suffix(shown))
    }

    // MARK: Rules

    private static let secretPatterns: [NSRegularExpression] = [
        #"sk-[A-Za-z0-9_\-]{20,}"#,                   // OpenAI, Anthropic and similar
        #"gh[pousr]_[A-Za-z0-9]{30,}"#,               // GitHub tokens
        #"github_pat_[A-Za-z0-9_]{30,}"#,
        #"AKIA[0-9A-Z]{16}"#,                         // AWS access key IDs
        #"AIza[0-9A-Za-z_\-]{35}"#,                   // Google API keys
        #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,            // Slack tokens
        #"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#,  // JSON web tokens
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ].map { try! NSRegularExpression(pattern: $0) }
    /// "password: hunter22", "API_KEY=…": the value after the label.
    private static let labeledSecret = try! NSRegularExpression(
        pattern: #"(?i)\b(?:password|passwd|pwd|secret|token|api[_ \-]?key|access[_ \-]?key)\b\s*[:=]\s*["']?([^\s"']{6,})"#)
    private static let longToken = try! NSRegularExpression(pattern: #"[A-Za-z0-9_\-+/=]{24,}"#)
    private static let cardNumber = try! NSRegularExpression(pattern: #"\b\d(?:[ \-]?\d){12,18}\b"#)
    private static let socialSecurity = try! NSRegularExpression(pattern: #"\b(?!000|666|9\d\d)\d{3}-(?!00)\d{2}-(?!0000)\d{4}\b"#)
    private static let email = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)

    private static func ranges(of pattern: NSRegularExpression, in line: String, group: Int = 0) -> [Range<String.Index>] {
        pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { Range($0.range(at: group), in: line) }
    }

    private static func cleaned(_ terms: [String]) -> [String] {
        terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 2 }
    }

    /// A long run of letters and digits mixed together with little repetition, as keys are. Words, paths and
    /// long numbers are not.
    static func looksRandom(_ token: String) -> Bool {
        let letters = token.filter(\.isLetter).count, digits = token.filter(\.isNumber).count
        guard letters >= 6, digits >= 3, token.contains(where: \.isUppercase), token.contains(where: \.isLowercase) else { return false }
        var counts: [Character: Int] = [:]
        for character in token { counts[character, default: 0] += 1 }
        let length = Double(token.count)
        let entropy = counts.values.reduce(0.0) { sum, count in
            let p = Double(count) / length
            return sum - p * log2(p)
        }
        return entropy >= 3.5
    }

    /// The check digit every real card number passes, so a long order number or timestamp is not taken for one.
    static func passesLuhn(_ text: String) -> Bool {
        let digits = text.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count), Set(digits).count > 1 else { return false }
        let sum = digits.reversed().enumerated().reduce(0) { sum, item in
            guard item.offset % 2 == 1 else { return sum + item.element }
            let doubled = item.element * 2
            return sum + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }
}

/// Sensitive text seen on one sampled frame. `rect` is in the recorded picture, 0...1 from the top-left.
public struct SensitiveSighting: Equatable, Sendable {
    public var kind: SensitiveKind
    public var text: String
    public var time: Double
    public var rect: CGRect

    public init(kind: SensitiveKind, text: String, time: Double, rect: CGRect) {
        self.kind = kind
        self.text = text
        self.time = time
        self.rect = rect
    }
}

/// One piece of sensitive text over the stretch of the original recording where it was on screen, with the
/// area it covered.
public struct SensitiveFinding: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: SensitiveKind
    public var text: String
    /// Source-recording seconds, already widened so the frames between samples are covered.
    public var start: Double
    public var end: Double
    public var rect: CGRect

    public init(id: UUID = UUID(), kind: SensitiveKind, text: String, start: Double, end: Double, rect: CGRect) {
        self.id = id
        self.kind = kind
        self.text = text
        self.start = start
        self.end = end
        self.rect = rect
    }
}

public enum SensitiveScan {
    /// How often the recording is sampled, in seconds.
    public static let interval = 0.5
    /// A finding whose area would grow past this many times its first sighting (text scrolling a long way)
    /// starts a fresh stretch instead, so one blur does not swallow the screen.
    static let maximumGrowth = 4.0

    /// Joins sightings of the same text from frame to frame into stretches. A stretch follows its text as it
    /// moves, covering everywhere it went, and ends once the text has not been seen for more than a sample.
    /// Each stretch then starts a sample early and ends a sample late, and its area is padded, so the moments
    /// between samples and the edges of the letters stay hidden.
    public static func findings(from sightings: [SensitiveSighting], interval: Double = SensitiveScan.interval, duration: Double) -> [SensitiveFinding] {
        struct Open {
            var kind: SensitiveKind
            var key: String
            var text: String
            var first: Double
            var last: Double
            var rect: CGRect
            var firstArea: Double
        }
        var open: [Open] = []
        var closed: [Open] = []
        let byTime = Dictionary(grouping: sightings, by: \.time).sorted { $0.key < $1.key }

        for (time, frame) in byTime {
            // Close stretches whose text has gone.
            let (stale, live) = open.reduce(into: ([Open](), [Open]())) { split, item in
                if time - item.last > interval * 1.5 { split.0.append(item) } else { split.1.append(item) }
            }
            closed += stale
            open = live
            var claimed = Set<Int>()
            for sighting in frame {
                let key = normalized(sighting.text)
                let rect = sighting.rect
                let candidate = open.indices
                    .filter { !claimed.contains($0) && open[$0].kind == sighting.kind && open[$0].key == key && open[$0].last < time }
                    .min { distance(open[$0].rect, rect) < distance(open[$1].rect, rect) }
                if let index = candidate, distance(open[index].rect, rect) < 0.25 {
                    let grown = open[index].rect.union(rect)
                    if area(grown) <= open[index].firstArea * maximumGrowth {
                        open[index].rect = grown
                        open[index].last = time
                        claimed.insert(index)
                        continue
                    }
                    // Moved too far: end this stretch here and start another, overlapping in time so nothing shows.
                    var ended = open.remove(at: index)
                    ended.last = time
                    closed.append(ended)
                    claimed = Set(claimed.map { $0 > index ? $0 - 1 : $0 })
                }
                open.append(Open(kind: sighting.kind, key: key, text: sighting.text, first: time, last: time, rect: rect, firstArea: max(area(rect), 1e-6)))
                claimed.insert(open.count - 1)
            }
        }
        closed += open

        return closed.map { item in
            SensitiveFinding(
                kind: item.kind, text: item.text,
                start: max(0, item.first - interval), end: min(duration, item.last + interval),
                rect: padded(item.rect))
        }
        .sorted { ($0.start, $0.rect.minY) < ($1.start, $1.rect.minY) }
    }

    /// Blur marks for `finding` on the edited timeline: one for each kept part of the recording it was seen in,
    /// none if all of it was cut. A very short one is stretched to the shortest a mark can be.
    public static func blurs(for finding: SensitiveFinding, cuts: EditModel, blurRadius: Double = 0.015) -> [ShapeOverlay] {
        let total = cuts.keptDuration
        return cuts.outputSpans(forSource: TimeSpan(start: finding.start, end: finding.end)).map { span in
            var start = span.start, end = span.end
            if end - start < ShapeOverlay.minimumLength {
                end = min(total, start + ShapeOverlay.minimumLength)
                start = max(0, end - ShapeOverlay.minimumLength)
            }
            let rect = finding.rect
            return ShapeOverlay(
                kind: .blur, start: start, end: end,
                x1: rect.minX, y1: rect.minY, x2: rect.maxX, y2: rect.maxY, blurRadius: blurRadius)
        }
    }

    /// Padding around the letters: a quarter of the text's height above and below, a little to each side, and
    /// never smaller than a mark can be.
    static func padded(_ rect: CGRect) -> CGRect {
        var rect = rect.insetBy(dx: -0.008, dy: -rect.height * 0.25)
        if rect.width < ShapeOverlay.minimumSide { rect = rect.insetBy(dx: -(ShapeOverlay.minimumSide - rect.width) / 2, dy: 0) }
        if rect.height < ShapeOverlay.minimumSide { rect = rect.insetBy(dx: 0, dy: -(ShapeOverlay.minimumSide - rect.height) / 2) }
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    private static func area(_ rect: CGRect) -> Double { Double(rect.width * rect.height) }

    private static func distance(_ a: CGRect, _ b: CGRect) -> Double {
        Double(hypot(a.midX - b.midX, a.midY - b.midY))
    }
}
