import Foundation
import Observation
import SwiftData

enum CardStatus { case new, learning, learned }

struct DayActivity: Identifiable, Hashable {
    let day: Date
    var questions = 0
    var cards = 0
    /// Questions answered correctly, for the day's accuracy.
    var correctQuestions = 0
    var id: Date { day }

    var accuracy: Double? { questions == 0 ? nil : Double(correctQuestions) / Double(questions) }
}

/// The learner's own data, stored with SwiftData in Application Support/Rotonda, one store per
/// licence: Progress.store for A/B (the store from before licences existed) and
/// Progress-<licence>.store for the others (see `ProgressSchemaV2`). Answers, memory cards,
/// saved words and questions, exams and activity all belong to the licence being studied.
/// The helper language is not part of it, so changing language keeps all progress. Everything is kept in memory as well, so views read it
/// synchronously and update through Observation.
@MainActor
@Observable
final class ProgressStore {
    static let shared = ProgressStore()

    /// Answers to the current licence's questions, each with its chapter in that licence.
    private(set) var stats: [Int: QuestionStat] = [:]
    private(set) var cards: [String: CardState] = [:]
    private(set) var bookmarks: Set<Int> = []
    /// Saved words by id, with when they were saved.
    private(set) var savedWords: [Int: Date] = [:]
    private(set) var readingPositions: [String: Int] = [:]
    /// The current licence's mock exams, newest first.
    private(set) var exams: [ExamRecord] = []
    private(set) var lastSession: StudySession?
    private(set) var glosses: [String: String] = [:]
    private(set) var activity: [DayActivity] = []

    @ObservationIgnored private var container: ModelContainer?
    private var context: ModelContext? { container?.mainContext }
    /// Small app state (the session to continue, today's challenge) lives in UserDefaults;
    /// SwiftData holds the growing study records.
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum StateKey {
        static let lastSession = "progress.lastSession"
        static let all = [lastSession, DailyChallenge.stateKey]
    }

    /// App state that names questions or chapters is kept per licence. A/B keeps the original
    /// keys, so state saved before licences existed still applies.
    static func licenceKey(_ key: String, _ licence: Licence) -> String {
        licence == .ab ? key : "\(key).\(licence.rawValue)"
    }

    static func licenceKey(_ key: String) -> String { licenceKey(key, ContentStore.shared.licence) }

    private init() {
        container = Self.openStore(for: ContentStore.shared.licence)
        load()
    }

    /// The licence's own store file. A/B keeps the original name, so its progress carries over.
    static func storeURL(for licence: Licence) -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rotonda", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(licence == .ab ? "Progress.store" : "Progress-\(licence.rawValue).store")
    }

    private static func openStore(for licence: Licence) -> ModelContainer? {
        let schema = Schema(versionedSchema: ProgressSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL(for: licence), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, migrationPlan: ProgressMigrationPlan.self, configurations: configuration)
        } catch {
            print("Progress store unavailable: \(error)")
            return nil
        }
    }

    // MARK: Questions

    /// `hesitant`: correct, but slow enough to count as unsure. It keeps the current interval
    /// and does not count toward clearing a mistake.
    func record(_ question: Question, answer: Bool, hesitant: Bool = false) {
        let correct = answer == question.answer
        var stat = stats[question.id] ?? QuestionStat(chapterID: question.chapterID)
        stat.attempts += 1
        if correct {
            stat.correct += 1
            if !hesitant { stat.streak += 1 }
        } else {
            stat.wrong += 1
            stat.streak = 0
        }
        stat.lastCorrect = correct
        stat.lastAt = .now
        stats[question.id] = stat
        let id = question.id
        let row = first(#Predicate<StoredQuestionStat> { $0.questionID == id })
            ?? insert(StoredQuestionStat(questionID: id, chapterID: stat.chapterID))
        row?.attempts = stat.attempts
        row?.correct = stat.correct
        row?.wrong = stat.wrong
        row?.streak = stat.streak
        row?.lastCorrect = stat.lastCorrect
        row?.lastAt = stat.lastAt
        log(kind: "question", item: String(question.id), correct: correct)
    }

    var mistakeIDs: [Int] {
        stats.filter { $0.value.isMistake }.sorted { $0.value.lastAt > $1.value.lastAt }.map(\.key)
    }

    /// Both successful answers and mistakes return only after their review interval.
    var dueQuestionIDs: [Int] {
        let now = Date.now
        return stats.filter { $0.value.reviewDue <= now }
            .sorted { $0.value.reviewDue == $1.value.reviewDue ? $0.key < $1.key : $0.value.reviewDue < $1.value.reviewDue }
            .map(\.key)
    }

    func mistakeIDs(chapter: Int) -> [Int] {
        stats.filter { $0.value.isMistake && $0.value.chapterID == chapter }.map(\.key).sorted()
    }

    struct ChapterSummary {
        var answered = 0
        var correct = 0
        var mistakes = 0
    }

    func summary(chapter: Int) -> ChapterSummary {
        stats.values.reduce(into: ChapterSummary()) { result, stat in
            guard stat.chapterID == chapter else { return }
            result.answered += 1
            if stat.lastCorrect { result.correct += 1 }
            if stat.isMistake { result.mistakes += 1 }
        }
    }

    /// Share of the whole bank whose latest answer was correct.
    var bankMastery: Double {
        let total = ContentStore.shared.questionCount
        return total == 0 ? 0 : Double(stats.values.filter(\.lastCorrect).count) / Double(total)
    }

    var recentAccuracy: Double? {
        let recent = stats.values.sorted { $0.lastAt > $1.lastAt }.prefix(100)
        return recent.isEmpty ? nil : Double(recent.filter(\.lastCorrect).count) / Double(recent.count)
    }

    func toggleBookmark(_ id: Int) {
        if bookmarks.remove(id) != nil {
            delete(#Predicate<StoredBookmark> { $0.questionID == id })
        } else {
            bookmarks.insert(id)
            insert(StoredBookmark(questionID: id))
        }
        save()
    }

    /// Saved words, most recently saved first.
    var savedWordIDs: [Int] { savedWords.sorted { $0.value > $1.value }.map(\.key) }

    func toggleSavedWord(_ id: Int) {
        if savedWords.removeValue(forKey: id) != nil {
            delete(#Predicate<StoredSavedWord> { $0.wordID == id })
        } else {
            let now = Date.now
            savedWords[id] = now
            insert(StoredSavedWord(wordID: id, at: now))
        }
        save()
    }

    // MARK: Cards

    func status(_ cardID: String) -> CardStatus {
        guard let card = cards[cardID] else { return .new }
        return card.isLearned ? .learned : .learning
    }

    func review(_ cardID: String, known: Bool, hesitant: Bool = false) {
        var card = cards[cardID] ?? CardState(box: -1)
        if known && hesitant {
            // Unsure: comes back tomorrow at the latest, and the interval does not grow.
            card.box = max(card.box, 1)
        } else if known {
            // A brand-new card the learner already knows skips straight to a few days out.
            card.box = card.box < 0 ? CardState.learnedBox : min(card.box + 1, CardState.intervals.count - 1)
        } else {
            card.box = 0
            card.lapses += 1
        }
        card.reps += 1
        card.due = .now.addingTimeInterval(CardState.intervals[card.box])
        cards[cardID] = card
        if let row = first(#Predicate<StoredCard> { $0.cardID == cardID }) {
            row.box = card.box
            row.due = card.due
            row.reps = card.reps
            row.lapses = card.lapses
            row.lastAt = .now
        } else {
            insert(StoredCard(cardID: cardID, box: card.box, due: card.due, reps: card.reps, lapses: card.lapses))
        }
        log(kind: "card", item: cardID, correct: known)
    }

    func forget(_ cardID: String) {
        cards[cardID] = nil
        delete(#Predicate<StoredCard> { $0.cardID == cardID })
        save()
    }

    func dueCardIDs(prefix: String) -> [String] {
        let now = Date.now
        return cards.filter { $0.key.hasPrefix(prefix) && $0.value.isDue(at: now) }
            .sorted { $0.value.due < $1.value.due }.map(\.key)
    }

    func learnedCount(prefix: String) -> Int {
        cards.filter { $0.key.hasPrefix(prefix) && $0.value.isLearned }.count
    }

    func learnedCount(_ cardIDs: [String]) -> Int {
        cardIDs.filter { cards[$0]?.isLearned == true }.count
    }

    // MARK: Reading positions, last session, exams

    func readingPosition(_ key: String) -> Int { readingPositions[key] ?? 0 }

    func setReadingPosition(_ position: Int, for key: String) {
        guard readingPositions[key] != position else { return }
        readingPositions[key] = position
        if let row = first(#Predicate<StoredReadingPosition> { $0.key == key }) {
            row.position = position
            row.at = .now
        } else {
            insert(StoredReadingPosition(key: key, position: position))
        }
        save()
    }

    /// A small piece of app state from UserDefaults, stored as a property list.
    func state<Value: Decodable>(_ type: Value.Type, for key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? PropertyListDecoder().decode(type, from: $0) }
    }

    func setState<Value: Encodable>(_ value: Value, for key: String) {
        guard let data = try? PropertyListEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    func setLastSession(_ session: StudySession) {
        guard session.isResumable else { return }
        lastSession = session
        setState(session, for: Self.licenceKey(StateKey.lastSession))
    }

    func saveExam(questions: [Question], answers: [Int: Bool], seconds: Int) -> ExamRecord {
        let errors = questions.filter { answers[$0.id] != $0.answer }.count
        var latest = FetchDescriptor<StoredExam>(sortBy: [SortDescriptor(\.examID, order: .reverse)])
        latest.fetchLimit = 1
        let examID = ((try? context?.fetch(latest).first?.examID) ?? 0) + 1
        let licence = ContentStore.shared.licence
        if let exam = insert(StoredExam(examID: examID, at: .now, correct: questions.count - errors, errors: errors,
                                        duration: seconds, licence: licence.rawValue)) {
            // Every statement in exam order; an unanswered one has no answer.
            exam.answers = questions.enumerated().map { position, question in
                StoredExamAnswer(position: position, questionID: question.id, answer: answers[question.id])
            }
        }
        // As in the official test, a statement left unanswered is an error — and a mistake to study.
        for question in questions {
            record(question, answer: answers[question.id] ?? !question.answer)
        }
        loadExams()
        return exams.first ?? ExamRecord(id: 0, date: .now, correct: questions.count - errors, errors: errors, durationSeconds: seconds,
                                          answers: answers, licence: licence, maxErrors: ContentStore.shared.examRules.maxErrors)
    }

    func examQuestionIDs(_ exam: ExamRecord) -> [Int] {
        let examID = exam.id
        return first(#Predicate<StoredExam> { $0.examID == examID })?.answers
            .sorted { $0.position < $1.position }.map(\.questionID) ?? []
    }

    // MARK: Glosses translated on device

    func gloss(word: Int, language: HelperLanguage) -> String? { glosses["\(word)|\(language.rawValue)"] }

    func saveGloss(_ text: String, word: Int, language: HelperLanguage) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let key = "\(word)|\(language.rawValue)"
        glosses[key] = clean
        if let row = first(#Predicate<StoredGloss> { $0.key == key }) {
            row.text = clean
        } else {
            insert(StoredGloss(key: key, text: clean))
        }
        save()
    }

    /// Consecutive days with at least one answer, counting back from today or yesterday.
    func streakDays() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let since = calendar.date(byAdding: .day, value: -365, to: today) else { return 0 }
        let days = Set(activity(since: since).map { calendar.startOfDay(for: $0.at) })
        var day = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var count = 0
        while days.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    // MARK: Reset

    func resetAll() {
        if let context {
            // Translated meanings are a cache, not progress, so they stay.
            try? context.delete(model: StoredExamAnswer.self)
            try? context.delete(model: StoredExam.self)
            try? context.delete(model: StoredQuestionStat.self)
            try? context.delete(model: StoredCard.self)
            try? context.delete(model: StoredBookmark.self)
            try? context.delete(model: StoredSavedWord.self)
            try? context.delete(model: StoredReadingPosition.self)
            try? context.delete(model: StoredActivity.self)
            save()
        }
        for key in StateKey.all {
            for licence in Licence.allCases { defaults.removeObject(forKey: Self.licenceKey(key, licence)) }
        }
        load()
    }

    // MARK: Storage

    private func log(kind: String, item: String, correct: Bool) {
        insert(StoredActivity(kind: kind, item: item, correct: correct))
        save()
        let today = Calendar.current.startOfDay(for: .now)
        if let index = activity.firstIndex(where: { $0.day == today }) {
            if kind == "question" {
                activity[index].questions += 1
                if correct { activity[index].correctQuestions += 1 }
            } else {
                activity[index].cards += 1
            }
        }
    }

    /// The learner chose another licence: switch to its own progress.
    func licenceDidChange() {
        save()
        container = Self.openStore(for: ContentStore.shared.licence)
        load()
    }

    private func load() {
        // Chapters come from the content, not the stored copy, so they follow content updates.
        // Answers to questions the content no longer has (removed from the official bank) stay
        // stored but are left out, so mistake and review counts only offer questions that exist.
        let chapters = ContentStore.shared.chapterIDs()
        stats = Dictionary(fetch(StoredQuestionStat.self).compactMap { row in
            guard let chapterID = chapters[row.questionID] else { return nil }
            return (row.questionID, QuestionStat(chapterID: chapterID, attempts: row.attempts, correct: row.correct, wrong: row.wrong,
                                                 streak: row.streak, lastCorrect: row.lastCorrect, lastAt: row.lastAt))
        }, uniquingKeysWith: { first, _ in first })
        cards = Dictionary(fetch(StoredCard.self).map { row in
            (row.cardID, CardState(box: row.box, due: row.due, reps: row.reps, lapses: row.lapses))
        }, uniquingKeysWith: { first, _ in first })
        bookmarks = Set(fetch(StoredBookmark.self).map(\.questionID))
        savedWords = Dictionary(fetch(StoredSavedWord.self).map { ($0.wordID, $0.at) }, uniquingKeysWith: { first, _ in first })
        readingPositions = Dictionary(fetch(StoredReadingPosition.self).map { ($0.key, $0.position) }, uniquingKeysWith: { first, _ in first })
        glosses = Dictionary(fetch(StoredGloss.self).map { ($0.key, $0.text) }, uniquingKeysWith: { first, _ in first })
        lastSession = state(StudySession.self, for: Self.licenceKey(StateKey.lastSession))
        loadExams()
        loadActivity()
    }

    private func loadExams() {
        let licence = ContentStore.shared.licence.rawValue
        var recent = FetchDescriptor<StoredExam>(predicate: #Predicate { $0.licence == licence },
                                                 sortBy: [SortDescriptor(\.at, order: .reverse)])
        recent.fetchLimit = 50
        let rules = ContentStore.shared.examRules
        exams = ((try? context?.fetch(recent)) ?? []).map { exam in
            let answers = exam.answers.compactMap { row in row.answer.map { (row.questionID, $0) } }
            return ExamRecord(id: exam.examID, date: exam.at, correct: exam.correct, errors: exam.errors,
                              durationSeconds: exam.duration, answers: Dictionary(answers, uniquingKeysWith: { first, _ in first }),
                              licence: ContentStore.shared.licence, maxErrors: rules.maxErrors)
        }
    }

    private func loadActivity() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map { DayActivity(day: $0) }
        for entry in activity(since: days[0].day) {
            let day = calendar.startOfDay(for: entry.at)
            guard let index = days.firstIndex(where: { $0.day == day }) else { continue }
            if entry.kind == "question" {
                days[index].questions += 1
                if entry.correct { days[index].correctQuestions += 1 }
            } else {
                days[index].cards += 1
            }
        }
        activity = days
    }

    // MARK: SwiftData helpers

    private func activity(since date: Date) -> [StoredActivity] {
        (try? context?.fetch(FetchDescriptor<StoredActivity>(predicate: #Predicate { $0.at >= date }))) ?? []
    }

    private func fetch<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
        (try? context?.fetch(FetchDescriptor<Model>())) ?? []
    }

    private func first<Model: PersistentModel>(_ predicate: Predicate<Model>) -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context?.fetch(descriptor).first
    }

    @discardableResult
    private func insert<Model: PersistentModel>(_ model: Model) -> Model? {
        guard let context else { return nil }
        context.insert(model)
        return model
    }

    private func delete<Model: PersistentModel>(_ predicate: Predicate<Model>) {
        try? context?.delete(model: Model.self, where: predicate)
    }

    /// Writes changes straight away, so closing the app mid-session loses nothing.
    private func save() {
        guard let context, context.hasChanges else { return }
        do { try context.save() } catch { print("Progress not saved: \(error)") }
    }
}
