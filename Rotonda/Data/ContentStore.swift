import Foundation

/// Read-only access to the bundled `patente.db` (built by Scripts/build_content_db.py).
/// Everything here works offline.
///
/// Questions are stored once by official number; chapters, groups, word rankings and facts
/// belong to a licence. Every query is scoped to `licence`, the one the learner chose, so the
/// rest of the app sees a single licence's bank.
@MainActor
final class ContentStore {
    static let shared = ContentStore()

    private let db: SQLiteDatabase?
    let loadError: String?

    /// Changing it reloads the licence's chapters, facts and exam rules.
    var licence: Licence {
        didSet { if licence != oldValue { reload() } }
    }

    private(set) var chapters: [Chapter] = []
    private(set) var questionCount = 0
    private(set) var wordCount = 0
    private(set) var allFacts: [Fact] = []
    private(set) var examRules = ExamRules.standard
    private var coverage: [Int: Double] = [:]
    private(set) lazy var meta: [String: String] = Dictionary(
        uniqueKeysWithValues: db?.query("SELECT key, value FROM meta") { ($0.text(0), $0.text(1)) } ?? []
    )

    /// Licences in the database, so a licence missing from an older bundle is never offered.
    private(set) lazy var availableLicences: Set<Licence> = Set(
        db?.query("SELECT id FROM licences") { Licence(rawValue: $0.text(0)) }.compactMap { $0 } ?? []
    )

    /// Percent of content words in question text covered by the top `n` ranked words.
    func coverage(top n: Int) -> Double { coverage[n] ?? 0 }

    /// The licence's id as an SQL literal. Licence ids are fixed identifiers, never user text.
    private var scope: String { "'\(licence.rawValue)'" }

    private init() {
        // The stored choice (`Preferences.licence`), read directly so the store stands alone.
        licence = UserDefaults.standard.string(forKey: "licence").flatMap(Licence.init) ?? .ab
        guard let url = Bundle.main.url(forResource: "patente", withExtension: "db") else {
            db = nil
            loadError = "patente.db is missing from the app bundle."
            return
        }
        do {
            db = try SQLiteDatabase(path: url.path, readOnly: true)
            loadError = nil
        } catch {
            db = nil
            loadError = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        guard let db else { return }
        chapters = db.query("""
            SELECT c.id, c.position, c.title_it, c.short_it, c.question_count, c.image_group_count, c.exam_quota
                   \(Self.columns("title", "short"))
            FROM chapters c \(Self.joins("chapter_texts", key: "chapter_id", to: "c.id"))
            WHERE c.licence = \(scope) ORDER BY c.position
            """) { r in
            Chapter(id: r.int(0), position: r.int(1), titleIT: r.text(2), titles: Self.localized(r, from: 7, field: 0, of: 2),
                    shortIT: r.text(3), shorts: Self.localized(r, from: 7, field: 1, of: 2),
                    questionCount: r.int(4), imageGroupCount: r.int(5), examQuota: r.double(6))
        }
        let row = db.first("""
            SELECT question_count, word_count, exam_questions, exam_seconds, exam_max_errors,
                   coverage_100, coverage_250, coverage_500, coverage_1000, coverage_2000
            FROM licences WHERE id = \(scope)
            """) { r in
            (questions: r.int(0), words: r.int(1),
             rules: ExamRules(questionCount: r.int(2), seconds: r.int(3), maxErrors: r.int(4)),
             coverage: Dictionary(uniqueKeysWithValues: zip([100, 250, 500, 1000, 2000], (Int32(5)...9).map { r.double($0) })))
        }
        questionCount = row?.questions ?? 0
        wordCount = row?.words ?? 0
        examRules = row?.rules ?? .standard
        coverage = row?.coverage ?? [:]
        allFacts = db.query(factSelect + " ORDER BY f.deck, f.position", map: Self.fact)
        wordForms = nil
    }

    /// The chapter of each question in the current licence.
    func chapterIDs() -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: db?.query("SELECT question_id, chapter_id FROM licence_questions WHERE licence = \(scope)") {
            ($0.int(0), $0.int(1))
        } ?? [])
    }

    /// Whether the licence's questions come with pictures; the CQC banks have none.
    var hasPictures: Bool { chapters.contains { $0.imageGroupCount > 0 } }

    func chapter(_ id: Int) -> Chapter? { chapters.first { $0.id == id } }

    // MARK: Translations

    /// Translations live in `*_texts` tables, one row per helper language. Each query joins one
    /// row per language (aliases t0, t1, …, in `HelperLanguage.allCases` order) and reads the
    /// columns into `Localized` values.
    private static let languages = HelperLanguage.allCases

    private static func alias(_ language: HelperLanguage) -> String { "t\(languages.firstIndex(of: language) ?? 0)" }

    private static func joins(_ table: String, key: String, to column: String) -> String {
        languages.map { language in
            "LEFT JOIN \(table) \(alias(language)) ON \(alias(language)).\(key) = \(column) AND \(alias(language)).language = '\(language.rawValue)'"
        }.joined(separator: " ")
    }

    /// ", t0.a, t0.b, t1.a, t1.b, …"
    private static func columns(_ names: String...) -> String {
        languages.map { language in names.map { ", \(alias(language)).\($0)" }.joined() }.joined()
    }

    /// Field `field` of `count` per language, from column `start` on.
    private static func localized(_ r: SQLiteRow, from start: Int32, field: Int32, of count: Int32) -> Localized {
        var values: [HelperLanguage: String] = [:]
        for (index, language) in languages.enumerated() {
            let value = r.text(start + Int32(index) * count + field)
            if !value.isEmpty { values[language] = value }
        }
        return Localized(values: values)
    }

    // MARK: Questions

    /// Questions with their place in the current licence; questions outside it never match.
    private var questionSelect: String {
        """
        SELECT q.id, m.chapter_id, m.group_id, m.position, q.text_it, q.answer, q.image, q.expl_it
               \(Self.columns("text", "explanation"))
        FROM questions q JOIN licence_questions m ON m.question_id = q.id AND m.licence = \(scope)
        \(Self.joins("question_texts", key: "question_id", to: "q.id"))
        """
    }

    private static func question(_ r: SQLiteRow) -> Question {
        Question(id: r.int(0), chapterID: r.int(1), groupID: r.int(2), position: r.int(3),
                 textIT: r.text(4), texts: localized(r, from: 8, field: 0, of: 2), answer: r.bool(5),
                 image: r.optionalText(6), explanationIT: r.text(7), explanations: localized(r, from: 8, field: 1, of: 2))
    }

    func questions(chapter: Int) -> [Question] {
        db?.query(questionSelect + " WHERE m.chapter_id = ? ORDER BY m.position", [chapter], map: Self.question) ?? []
    }

    /// Full practice bank; selection must consider every unseen statement before reviews.
    func studyQuestions(withImagesOnly: Bool = false) -> [Question] {
        let filter = withImagesOnly ? " WHERE q.image IS NOT NULL" : ""
        return db?.query(questionSelect + filter + " ORDER BY m.chapter_id, m.position", map: Self.question) ?? []
    }

    func questions(group: Int) -> [Question] {
        db?.query(questionSelect + " WHERE m.group_id = ? ORDER BY q.id", [group], map: Self.question) ?? []
    }

    /// Returns questions in the order of `ids`.
    func questions(ids: [Int]) -> [Question] {
        guard let db, !ids.isEmpty else { return [] }
        var byID: [Int: Question] = [:]
        for start in stride(from: 0, to: ids.count, by: 500) {
            let slice = Array(ids[start..<min(start + 500, ids.count)])
            let marks = Array(repeating: "?", count: slice.count).joined(separator: ",")
            for question in db.query(questionSelect + " WHERE q.id IN (\(marks))", slice, map: Self.question) {
                byID[question.id] = question
            }
        }
        return ids.compactMap { byID[$0] }
    }

    func question(_ id: Int) -> Question? { questions(ids: [id]).first }

    func randomQuestions(_ count: Int, excluding: Set<Int> = []) -> [Question] {
        let pool = db?.query("SELECT question_id FROM licence_questions WHERE licence = \(scope) ORDER BY RANDOM() LIMIT ?",
                             [count + excluding.count]) { $0.int(0) } ?? []
        return questions(ids: Array(pool.filter { !excluding.contains($0) }.prefix(count)))
    }

    /// A mock exam: each chapter supplies its share (`examQuota`), like the real exam's spread;
    /// fractions go to the chapters with the largest remainders.
    func examQuestions() -> [Question] {
        let total = examRules.questionCount
        var counts = chapters.map { Int($0.examQuota) }
        let order = chapters.indices.sorted {
            chapters[$0].examQuota - Double(counts[$0]) > chapters[$1].examQuota - Double(counts[$1])
        }
        for index in order where counts.reduce(0, +) < total { counts[index] += 1 }
        var ids: [Int] = []
        for (chapter, count) in zip(chapters, counts) where count > 0 {
            ids += db?.query("SELECT question_id FROM licence_questions WHERE chapter_id = ? ORDER BY RANDOM() LIMIT ?",
                             [chapter.id, count]) { $0.int(0) } ?? []
        }
        return questions(ids: ids.shuffled())
    }

    func imageGroups(chapter: Int?, matching query: String = "", language: HelperLanguage = .english) -> [QuestionGroup] {
        var filter = chapter == nil ? "" : " AND chapter_id = ?"
        var arguments: [Any] = chapter.map { [$0] } ?? []
        filter += " AND licence = \(scope)"
        let term = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if !term.isEmpty {
            let escaped = term.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
            filter += """
                 AND image IN (SELECT g.image FROM groups g JOIN licence_questions m ON m.group_id = g.id
                 JOIN questions q ON q.id = m.question_id
                 LEFT JOIN question_texts t ON t.question_id = q.id AND t.language = '\(language.rawValue)'
                 WHERE (q.fold_it LIKE ? ESCAPE '\\' OR t.text LIKE ? ESCAPE '\\' OR t.fold LIKE ? ESCAPE '\\')
                \(chapter == nil ? "" : " AND m.chapter_id = ?"))
                """
            arguments += ["%\(escaped)%", "%\(escaped)%", "%\(escaped)%"]
            if let chapter { arguments.append(chapter) }
        }
        return db?.query("""
            SELECT image, SUM(question_count) FROM groups
            WHERE image IS NOT NULL\(filter)
            GROUP BY image ORDER BY MIN(chapter_id), MIN(position), image
            """, arguments) { r in
            QuestionGroup(image: r.text(0), questionCount: r.int(1))
        } ?? []
    }

    /// Match all source groups for this picture, preserving an optional chapter scope.
    func questions(image: String, chapter: Int?) -> [Question] {
        let filter = chapter == nil ? "" : " AND chapter_id = ?"
        var arguments: [Any] = [image]
        if let chapter { arguments.append(chapter) }
        return db?.query(questionSelect + """
             WHERE m.group_id IN (SELECT id FROM groups WHERE image = ? AND licence = \(scope)\(filter))
             ORDER BY m.chapter_id, m.position, q.id
            """, arguments, map: Self.question) ?? []
    }

    // MARK: Words

    /// Words with their counts and rank in the current licence; words it never uses don't match.
    private var wordSelect: String {
        """
        SELECT w.id, w.lemma, w.kind, w.pos, w.level, w.example_it,
               l.question_count, l.true_count, l.chapter_spread, l.rank \(Self.columns("gloss", "note", "example"))
        FROM words w JOIN licence_words l ON l.word_id = w.id AND l.licence = \(scope)
        \(Self.joins("word_texts", key: "word_id", to: "w.id"))
        """
    }

    private static func word(_ r: SQLiteRow) -> Word {
        Word(id: r.int(0), lemma: r.text(1), kind: Word.Kind(rawValue: r.text(2)) ?? .general,
             partOfSpeech: r.text(3), level: r.optionalText(4), glosses: localized(r, from: 10, field: 0, of: 3),
             notes: localized(r, from: 10, field: 1, of: 3), exampleIT: r.text(5), examples: localized(r, from: 10, field: 2, of: 3),
             questionCount: r.int(6), trueCount: r.int(7), chapterSpread: r.int(8), rank: r.int(9))
    }

    func word(_ id: Int) -> Word? { db?.first(wordSelect + " WHERE w.id = ?", [id], map: Self.word) }

    func words(ids: [Int]) -> [Word] {
        guard let db, !ids.isEmpty else { return [] }
        let marks = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let byID = Dictionary(uniqueKeysWithValues: db.query(wordSelect + " WHERE w.id IN (\(marks))", ids, map: Self.word).map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Resolves any surface form the learner taps ("vietata") to its study word ("vietato").
    /// Every word form that opens a study card, loaded once, to mark those words in text.
    private var wordForms: Set<String>?

    func hasWord(forForm form: String) -> Bool {
        if wordForms == nil {
            wordForms = Set(db?.query("""
                SELECT f.form FROM word_forms f JOIN licence_words l ON l.word_id = f.word_id AND l.licence = \(scope)
                """) { $0.text(0) } ?? [])
        }
        return wordForms?.contains(Self.normalize(form)) == true
    }

    func word(forForm form: String) -> Word? {
        let key = Self.normalize(form)
        return db?.first(wordSelect + " WHERE w.id IN (SELECT word_id FROM word_forms WHERE form = ?) ORDER BY w.id LIMIT 1", [key], map: Self.word)
    }

    func rankedWords(limit: Int, offset: Int = 0) -> [Word] {
        db?.query(wordSelect + " ORDER BY l.rank LIMIT ? OFFSET ?", [limit, offset], map: Self.word) ?? []
    }

    func words(kind: Word.Kind) -> [Word] {
        db?.query(wordSelect + " WHERE w.kind = ? ORDER BY l.rank", [kind.rawValue], map: Self.word) ?? []
    }

    func chapterWords(_ chapter: Int, limit: Int = 60) -> [Word] {
        let ids = db?.query("SELECT word_id FROM chapter_words WHERE chapter_id = ? ORDER BY score DESC LIMIT ?", [chapter, limit]) { $0.int(0) } ?? []
        return words(ids: ids)
    }

    func questionIDs(word: Int) -> [Int] {
        db?.query("""
            SELECT wq.question_id FROM word_questions wq
            JOIN licence_questions m ON m.question_id = wq.question_id AND m.licence = \(scope)
            WHERE wq.word_id = ? ORDER BY wq.question_id
            """, [word]) { $0.int(0) } ?? []
    }

    /// Content words of a question, most useful first.
    func words(inQuestion question: Int) -> [Word] {
        db?.query(wordSelect + " WHERE w.id IN (SELECT word_id FROM word_questions WHERE question_id = ?) ORDER BY w.kind = 'general', l.rank LIMIT 12",
                  [question], map: Self.word) ?? []
    }

    /// Every (question, key word) link in the bank.
    func questionWordPairs() -> [(Int, Int)] {
        db?.query("""
            SELECT wq.question_id, wq.word_id FROM licence_questions m
            CROSS JOIN word_questions wq ON wq.question_id = m.question_id
            WHERE m.licence = \(scope)
            """) { ($0.int(0), $0.int(1)) } ?? []
    }

    func forms(word: Int) -> [String] {
        db?.query("SELECT form FROM word_forms WHERE word_id = ? ORDER BY form", [word]) { $0.text(0) } ?? []
    }

    // MARK: Facts

    /// The current licence's facts, each in its chapter of that licence.
    private var factSelect: String {
        """
        SELECT f.id, f.deck, lf.chapter_id, f.topic_it, f.text_it, f.value, f.note \(Self.columns("topic", "text"))
        FROM facts f JOIN licence_facts lf ON lf.fact_id = f.id AND lf.licence = \(scope)
        \(Self.joins("fact_texts", key: "fact_id", to: "f.id"))
        """
    }

    private static func fact(_ r: SQLiteRow) -> Fact {
        Fact(id: r.text(0), deck: FactDeck(rawValue: r.text(1)) ?? .concepts, chapterID: r.optionalInt(2),
             topics: localized(r, from: 7, field: 0, of: 2), topicIT: r.text(3), texts: localized(r, from: 7, field: 1, of: 2),
             textIT: r.text(4), value: r.text(5), note: r.text(6))
    }

    func facts(deck: FactDeck) -> [Fact] { allFacts.filter { $0.deck == deck } }
    func facts(chapter: Int) -> [Fact] { allFacts.filter { $0.chapterID == chapter } }
    func fact(_ id: String) -> Fact? { allFacts.first { $0.id == id } }

    func facts(forQuestion question: Int) -> [Fact] {
        let ids = Set(db?.query("SELECT fact_id FROM fact_questions WHERE question_id = ?", [question]) { $0.text(0) } ?? [])
        return allFacts.filter { ids.contains($0.id) }
    }

    /// The signs a fact talks about: distinct pictures from its linked questions, in order.
    func images(fact: String, limit: Int = 3) -> [String] {
        db?.query("""
            SELECT q.image FROM fact_questions fq JOIN questions q ON q.id = fq.question_id
            JOIN licence_questions m ON m.question_id = q.id AND m.licence = \(scope)
            WHERE fq.fact_id = ? AND q.image IS NOT NULL
            GROUP BY q.image ORDER BY MIN(q.id) LIMIT ?
            """, [fact, limit]) { $0.text(0) } ?? []
    }

    func questionIDs(fact: String) -> [Int] {
        db?.query("""
            SELECT fq.question_id FROM fact_questions fq
            JOIN licence_questions m ON m.question_id = fq.question_id AND m.licence = \(scope)
            WHERE fq.fact_id = ? ORDER BY fq.question_id
            """, [fact]) { $0.int(0) } ?? []
    }

    // MARK: Search

    struct SearchResults {
        var words: [Word] = []
        var questions: [Question] = []
        var facts: [Fact] = []
        var isEmpty: Bool { words.isEmpty && questions.isEmpty && facts.isEmpty }
    }

    /// Accent-insensitive search across Italian and the helper language.
    func search(_ text: String, language: HelperLanguage) -> SearchResults {
        let query = Self.fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let db, !query.isEmpty else { return SearchResults() }
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        let contains = "%\(escaped)%"
        let helper = Self.alias(language)
        var results = SearchResults()
        results.words = db.query(wordSelect + """
             WHERE w.fold LIKE ? ESCAPE '\\' OR w.id IN (SELECT word_id FROM word_forms WHERE form = ?)
                OR \(helper).gloss LIKE ? ESCAPE '\\'
             ORDER BY w.fold = ? DESC, w.fold LIKE ? ESCAPE '\\' DESC, l.rank LIMIT 30
            """, ["\(escaped)%", query, contains, query, "\(escaped)%"], map: Self.word)
        results.questions = db.query(questionSelect + """
             WHERE q.fold_it LIKE ? ESCAPE '\\' OR \(helper).text LIKE ? ESCAPE '\\' OR \(helper).fold LIKE ? ESCAPE '\\'
             ORDER BY m.chapter_id, m.position LIMIT 80
            """, [contains, contains, contains], map: Self.question)
        results.facts = allFacts.filter {
            [$0.topicIT, $0.textIT, $0.value, $0.topic(language), $0.text(language)]
                .contains { Self.fold($0).contains(query) }
        }
        return results
    }

    // MARK: Text helpers

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "it_IT"))
            .replacingOccurrences(of: "’", with: "'")
    }

    static func fold(_ text: String) -> String {
        normalize(text).folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
    }
}
