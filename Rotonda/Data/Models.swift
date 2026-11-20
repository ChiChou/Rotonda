import Foundation

/// The learner's support language. Italian is always the study language; the helper
/// language is how translations, glosses and explanations are shown.
///
/// Raw values are BCP 47 codes and match `languages.code` in patente.db. Adding a language is a
/// new case here plus its rows in the database and its UI strings; nothing is keyed by column.
enum HelperLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case chinese = "zh-Hans"
    case spanish = "es-419"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .chinese: "简体中文"
        case .spanish: "Español"
        }
    }

    var badge: String {
        switch self {
        case .english: "EN"
        case .chinese: "中"
        case .spanish: "ES"
        }
    }

    var speechLanguage: String {
        switch self {
        case .english: "en-US"
        case .chinese: "zh-CN"
        case .spanish: "es-MX"
        }
    }

    var localeLanguage: Locale.Language { Locale.Language(identifier: rawValue) }

    /// The helper language for a UI localization ("es", "zh-Hans", "en"…), if there is one.
    init?(localization: String) {
        guard let match = Self.allCases.first(where: {
            localization == $0.rawValue || Locale.Language(identifier: localization).languageCode == $0.localeLanguage.languageCode
        }) else { return nil }
        self = match
    }
}

/// Text in each helper language that has it. A language without the text reads as empty: the
/// app never shows another helper language in its place.
struct Localized: Hashable {
    var values: [HelperLanguage: String] = [:]

    subscript(_ language: HelperLanguage) -> String { values[language] ?? "" }

    var isEmpty: Bool { values.values.allSatisfy(\.isEmpty) }
}

struct Chapter: Identifiable, Hashable {
    let id: Int
    let position: Int
    let titleIT: String
    let titles: Localized
    let shortIT: String
    let shorts: Localized
    let questionCount: Int
    let imageGroupCount: Int
    /// How many mock-exam questions this chapter supplies on average.
    let examQuota: Double

    func shortTitle(_ language: HelperLanguage) -> String { shorts[language] }
    func title(_ language: HelperLanguage) -> String { titles[language] }
    var hasMoreTopics: Bool { titleIT != shortIT }
    /// The short Italian title without its bracketed gloss, for one-line headers:
    /// "Esempi di precedenza (ordine di precedenza agli incroci)" becomes "Esempi di precedenza".
    var topicIT: String {
        guard let bracket = shortIT.range(of: " (") else { return shortIT }
        return String(shortIT[..<bracket.lowerBound])
    }

    /// Matches the chapter number, its Italian topics or their translation in the helper language.
    @MainActor func matches(_ query: String, language: HelperLanguage) -> Bool {
        let term = ContentStore.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !term.isEmpty else { return true }
        return term == String(position) || ContentStore.fold("\(titleIT) \(title(language))").contains(term)
    }

    /// The official title's topics after the chapter's own name, each paired with its translation.
    /// When the languages don't split into the same parts, the whole title stays together.
    func topics(_ language: HelperLanguage) -> [(italian: String, translated: String)] {
        func parts(_ text: String) -> [String] {
            text.split(whereSeparator: { $0 == ";" || $0 == "；" })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let italian = parts(titleIT), translated = parts(title(language))
        guard italian.count == translated.count, italian.count > 1, italian.first == shortIT else {
            return [(titleIT, title(language))]
        }
        return Array(zip(italian, translated).dropFirst()).map { ($0, $1) }
    }
}

struct Question: Identifiable, Hashable {
    let id: Int
    let chapterID: Int
    let groupID: Int
    let position: Int
    let textIT: String
    let texts: Localized
    let answer: Bool
    let image: String?
    let explanationIT: String
    let explanations: Localized

    func text(_ language: HelperLanguage) -> String { texts[language] }

    var hasExplanation: Bool { !explanationIT.isEmpty || !explanations.isEmpty }

    /// The explanation in the helper language; empty when that language has none (Spanish has no
    /// explanations yet), so it is never shown as a "translation" of the Italian one.
    func explanation(_ language: HelperLanguage) -> String {
        Self.stripVerdict(explanations[language])
    }

    var italianExplanation: String { Self.stripVerdict(explanationIT) }

    /// Generated explanations start with a bracketed verdict ("[VERO] …", "【正确】…").
    /// The app shows the verdict itself, so it is removed from the body.
    private static func stripVerdict(_ value: String) -> String {
        let closing: Character? = value.first == "[" ? "]" : (value.first == "【" ? "】" : nil)
        guard let closing, let index = value.firstIndex(of: closing) else { return value }
        return value[value.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct QuestionGroup: Identifiable, Hashable {
    var id: String { image }
    let image: String
    let questionCount: Int
}

struct Word: Identifiable, Hashable {
    enum Kind: String { case exam, road, general }

    let id: Int
    let lemma: String
    let kind: Kind
    let partOfSpeech: String
    let level: String?
    let glosses: Localized
    let notes: Localized
    let exampleIT: String
    let examples: Localized
    let questionCount: Int
    let trueCount: Int
    let chapterSpread: Int
    let rank: Int

    var cardID: String { "w:\(id)" }
    var trueShare: Double { questionCount == 0 ? 0 : Double(trueCount) / Double(questionCount) }

    /// A missing Chinese meaning must never silently fall back to English.
    func meaning(_ language: HelperLanguage, cached: String? = nil) -> String? {
        let bundled = glosses[language].trimmingCharacters(in: .whitespacesAndNewlines)
        if !bundled.isEmpty { return bundled }
        guard let cached else { return nil }
        let clean = cached.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    func note(_ language: HelperLanguage) -> String { notes[language] }

    /// The example's translation in the helper language only, never another language.
    func exampleTranslation(_ language: HelperLanguage) -> String { examples[language] }

    /// The English meaning, the source for translating the meaning on device.
    var glossEN: String { glosses[.english] }
}

enum FactDeck: String, CaseIterable, Identifiable, Codable {
    case speed, licence, vehicle, signs, concepts, contrasts

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .speed: "Speed limits"
        case .licence: "Licence & points"
        case .vehicle: "Vehicles & loads"
        case .signs: "Sign facts"
        case .concepts: "Rules & definitions"
        case .contrasts: "Look-alike terms"
        }
    }

    var icon: String {
        switch self {
        case .speed: "gauge.with.dots.needle.67percent"
        case .licence: "person.text.rectangle"
        case .vehicle: "truck.box"
        case .signs: "exclamationmark.triangle"
        case .concepts: "book.closed"
        case .contrasts: "arrow.left.arrow.right"
        }
    }
}

struct Fact: Identifiable, Hashable {
    let id: String
    let deck: FactDeck
    let chapterID: Int?
    let topics: Localized
    let topicIT: String
    let texts: Localized
    let textIT: String
    let value: String
    let note: String

    var cardID: String { "f:\(id)" }

    func topic(_ language: HelperLanguage) -> String { topics[language] }
    func text(_ language: HelperLanguage) -> String { texts[language] }

    /// Many fact topics are written as "English (italiano)". Contrast cards carry Italian separately.
    var italianHeadline: String { topicIT.isEmpty ? textIT : topicIT }
}

/// The licence the learner studies for. Each one has its own official question bank (or part
/// of one), chapters, word ranking and mock exam; the raw value is stored in preferences and
/// in each mock exam and matches `licences.id` in patente.db.
enum Licence: String, CaseIterable, Identifiable, Codable {
    case ab, am, c, d
    case cqcGoods = "cqc_merci"
    case cqcPassengers = "cqc_persone"
    case revisionAB = "revisione_ab"
    case revisionAM = "revisione_am"
    case revisionCD = "revisione_superiori"
    case revisionCQCGoods = "revisione_cqc_merci"
    case revisionCQCPassengers = "revisione_cqc_persone"

    var id: String { rawValue }

    static let firstLicences: [Licence] = [.am, .ab, .c, .d, .cqcGoods, .cqcPassengers]
    static let revisions: [Licence] = [.revisionAM, .revisionAB, .revisionCD, .revisionCQCGoods, .revisionCQCPassengers]

    var isRevision: Bool { Self.revisions.contains(self) }

    /// The licence as Italians name it, never translated: "Patente B", "CQC merci".
    var name: String {
        switch self {
        case .ab, .revisionAB: "Patente A e B"
        case .am, .revisionAM: "Patente AM"
        case .c: "Patente C"
        case .d: "Patente D"
        case .revisionCD: "Patente C e D"
        case .cqcGoods, .revisionCQCGoods: "CQC merci"
        case .cqcPassengers, .revisionCQCPassengers: "CQC persone"
        }
    }

    /// What it lets you drive, in the helper language.
    var vehicles: LocalizedStringResource {
        switch self {
        case .ab, .revisionAB: "Car and motorcycle"
        case .am, .revisionAM: "Moped"
        case .c: "Truck"
        case .d: "Bus"
        case .revisionCD: "Truck and bus"
        case .cqcGoods, .revisionCQCGoods: "Professional goods driver"
        case .cqcPassengers, .revisionCQCPassengers: "Professional bus driver"
        }
    }

    var icon: String {
        switch self {
        case .ab, .revisionAB: "car.fill"
        case .am, .revisionAM: "scooter"
        case .c, .revisionCD: "truck.box.fill"
        case .d: "bus.fill"
        case .cqcGoods, .revisionCQCGoods: "shippingbox.fill"
        case .cqcPassengers, .revisionCQCPassengers: "person.2.fill"
        }
    }
}

struct ExamRecord: Identifiable, Hashable {
    let id: Int
    let date: Date
    let correct: Int
    let errors: Int
    let durationSeconds: Int
    let answers: [Int: Bool]
    let licence: Licence
    let maxErrors: Int

    var passed: Bool { errors <= maxErrors }
}

/// The official exam format of a licence, from patente.db.
struct ExamRules: Hashable {
    let questionCount: Int
    let seconds: Int
    let maxErrors: Int

    var minutes: Int { seconds / 60 }

    /// The A/B format, used when the database cannot be read.
    static let standard = ExamRules(questionCount: 30, seconds: 20 * 60, maxErrors: 3)
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

extension Word {
    @MainActor func matches(_ query: String, language: HelperLanguage) -> Bool {
        let term = ContentStore.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return term.isEmpty || ContentStore.fold(lemma).contains(term) ||
            ContentStore.fold(meaning(language) ?? "").contains(term)
    }
}
