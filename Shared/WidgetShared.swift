import Foundation

/// Data the app shares with its widgets through the App Group container. The app owns
/// the study databases; widgets read this snapshot and queue VERO/FALSO answers back.
nonisolated enum WidgetShared {
    static let appGroup = "group.me.chichou.rotonda"

    enum Kind {
        static let review = "RotondaReview"
        static let readiness = "RotondaReadiness"
        static let quiz = "RotondaQuiz"
        static let word = "RotondaWord"
    }

    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var imagesFolder: URL? { container?.appendingPathComponent("WidgetImages", isDirectory: true) }

    static func imageURL(_ name: String) -> URL? {
        imagesFolder?.appendingPathComponent((name as NSString).lastPathComponent)
    }

    private static let snapshotKey = "widget.snapshot"

    /// The latest snapshot, kept in the App Group's UserDefaults as a property list.
    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? PropertyListDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? PropertyListEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}

nonisolated struct WidgetSnapshot: Codable, Hashable {
    enum ReviewKind: String, Codable { case word, fact, question }

    struct Upcoming: Codable, Hashable {
        let kind: ReviewKind
        let due: Date
    }

    struct ReviewCounts: Codable, Hashable {
        var words = 0
        var facts = 0
        var questions = 0
        var total: Int { words + facts + questions }

        mutating func add(_ kind: ReviewKind) {
            switch kind {
            case .word: words += 1
            case .fact: facts += 1
            case .question: questions += 1
            }
        }
    }

    struct Exam: Codable, Hashable {
        let date: Date
        let errors: Int
        /// Missing in snapshots written before licences, which were all A/B exams.
        var maxErrors: Int?
        var passed: Bool { errors <= maxErrors ?? 3 }
    }

    struct Focus: Codable, Hashable {
        enum Reason: String, Codable { case mistakes, next }
        let chapterID: Int
        let position: Int
        let titleIT: String
        let titleHelper: String
        let reason: Reason
        let mistakes: Int
        let answered: Int
        let total: Int
    }

    struct QuizItem: Codable, Hashable {
        let id: Int
        let textIT: String
        let textHelper: String
        let answer: Bool
        let image: String?
        let isMistake: Bool
    }

    struct WordItem: Codable, Hashable {
        let id: Int
        let lemma: String
        let partOfSpeech: String
        let meaning: String?
        let example: String
        let isDue: Bool
    }

    var generated: Date
    var helperLanguage: String
    var showsTranslations: Bool

    var dueNow: ReviewCounts
    /// Reviews that fall due during the next few days, so counts grow without the app.
    var upcoming: [Upcoming]

    var mastered: Int
    var questionCount: Int
    var recentAccuracy: Double?
    var recentAnswers: Int
    var wordsLearned: Int
    /// Newest first.
    var exams: [Exam]
    var focus: Focus?
    /// Oldest first, ending today.
    var week: [Int]
    var streak: Int
    var studiedToday: Bool

    var quiz: [QuizItem]
    var words: [WordItem]

    var mastery: Double { questionCount == 0 ? 0 : Double(mastered) / Double(questionCount) }

    func dueCounts(at date: Date) -> ReviewCounts {
        upcoming.reduce(into: dueNow) { counts, item in
            if item.due <= date { counts.add(item.kind) }
        }
    }

    func nextDue(after date: Date) -> Date? {
        upcoming.lazy.map(\.due).filter { $0 > date }.min()
    }

    /// The licence's exam format; missing in snapshots written before licences (A/B: 30, 3).
    var examQuestions: Int?
    var examMaxErrors: Int?

    /// Chance of passing the licence's exam (at most 3 errors in 30 for A/B) at the recent accuracy.
    var passChance: Double? {
        let questions = examQuestions ?? 30
        guard let accuracy = recentAccuracy, recentAnswers >= min(questions, 30) else { return nil }
        return Self.passChance(accuracy: accuracy, questions: questions, maxErrors: examMaxErrors ?? 3)
    }

    static func passChance(accuracy: Double, questions: Int = 30, maxErrors: Int = 3) -> Double {
        let p = min(max(accuracy, 0), 1)
        var total = 0.0
        var combinations = 1.0
        for errors in 0...maxErrors {
            if errors > 0 { combinations *= Double(questions - errors + 1) / Double(errors) }
            total += combinations * pow(1 - p, Double(errors)) * pow(p, Double(questions - errors))
        }
        return min(max(total, 0), 1)
    }

    static let placeholder = WidgetSnapshot(
        generated: .now, helperLanguage: "en", showsTranslations: true,
        dueNow: ReviewCounts(words: 8, facts: 3, questions: 12), upcoming: [],
        mastered: 2_480, questionCount: 7_139, recentAccuracy: 0.91, recentAnswers: 100, wordsLearned: 214,
        exams: [Exam(date: .now, errors: 2), Exam(date: .now, errors: 5), Exam(date: .now, errors: 3), Exam(date: .now, errors: 1)],
        focus: Focus(chapterID: 5, position: 5, titleIT: "Precedenza", titleHelper: "Right of way", reason: .mistakes,
                     mistakes: 14, answered: 180, total: 260),
        week: [24, 0, 41, 18, 30, 12, 26], streak: 5, studiedToday: true,
        quiz: [QuizItem(id: 0, textIT: "Il segnale raffigurato preannuncia un incrocio con diritto di precedenza",
                        textHelper: "The sign shown warns of a crossroads where you have right of way",
                        answer: true, image: nil, isMistake: false)],
        words: [WordItem(id: 0, lemma: "carreggiata", partOfSpeech: "noun", meaning: "carriageway",
                         example: "La carreggiata è la parte della strada destinata ai veicoli.", isDue: false)])
}

/// Taps on a widget open the content it shows: a study session, or the exact statement
/// or word on screen.
nonisolated enum WidgetLink: Hashable {
    case review, exam, words, quiz
    case learn(chapter: Int)
    case chapterMistakes(chapter: Int)
    /// The statement on the widget. Answered ones open with their answer; open ones start
    /// a quiz with it first, followed by the rest of the widget deck.
    case statement(Int, answered: Bool, then: [Int])
    case word(Int)

    static let scheme = "rotonda"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "open"
        switch self {
        case .review: components.path = "/review"
        case .exam: components.path = "/exam"
        case .words: components.path = "/words"
        case .quiz: components.path = "/quiz"
        case .learn(let chapter): components.path = "/learn/\(chapter)"
        case .chapterMistakes(let chapter): components.path = "/mistakes/\(chapter)"
        case .word(let id): components.path = "/word/\(id)"
        case .statement(let id, let answered, let then):
            components.path = "/statement/\(id)"
            components.queryItems = [URLQueryItem(name: "answered", value: answered ? "1" : "0")]
            if !then.isEmpty {
                components.queryItems?.append(URLQueryItem(name: "then", value: then.map(String.init).joined(separator: ",")))
            }
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        switch (parts.first, parts.dropFirst().first.flatMap { Int($0) }) {
        case ("review", _): self = .review
        case ("exam", _): self = .exam
        case ("words", _): self = .words
        case ("quiz", _): self = .quiz
        case ("learn", let chapter?): self = .learn(chapter: chapter)
        case ("mistakes", let chapter?): self = .chapterMistakes(chapter: chapter)
        case ("word", let id?): self = .word(id)
        case ("statement", let id?):
            let then = (value("then") ?? "").split(separator: ",").compactMap { Int($0) }
            self = .statement(id, answered: value("answered") == "1", then: then)
        default: return nil
        }
    }
}

/// VERO/FALSO answers given in the widget, waiting for the app to record them.
nonisolated enum WidgetQuizState {
    private static let answersKey = "quiz.answers"
    private static let currentKey = "quiz.current"
    private static let revealedKey = "quiz.revealed"

    static var answers: [Int: Bool] {
        let stored = WidgetShared.defaults?.dictionary(forKey: answersKey) as? [String: Bool] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    static var current: Int? { WidgetShared.defaults?.object(forKey: currentKey) as? Int }
    static var revealed: Bool { WidgetShared.defaults?.bool(forKey: revealedKey) ?? false }

    static func answer(_ question: Int, _ value: Bool) {
        guard let defaults = WidgetShared.defaults else { return }
        var stored = defaults.dictionary(forKey: answersKey) as? [String: Bool] ?? [:]
        stored[String(question)] = value
        defaults.set(stored, forKey: answersKey)
        defaults.set(question, forKey: currentKey)
        defaults.set(true, forKey: revealedKey)
    }

    static func advance(to question: Int?) {
        guard let defaults = WidgetShared.defaults else { return }
        if let question { defaults.set(question, forKey: currentKey) } else { defaults.removeObject(forKey: currentKey) }
        defaults.set(false, forKey: revealedKey)
    }

    /// Hands queued answers to the app and starts the widget fresh on the next deck.
    static func drain() -> [Int: Bool] {
        let pending = answers
        guard let defaults = WidgetShared.defaults else { return pending }
        defaults.removeObject(forKey: answersKey)
        defaults.removeObject(forKey: currentKey)
        defaults.set(false, forKey: revealedKey)
        return pending
    }
}
