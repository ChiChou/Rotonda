import SwiftUI
import UIKit
import WidgetKit

/// Keeps the Home Screen widgets in step with study progress: records answers given in
/// the widget, then writes a fresh snapshot of what is due and what to study next.
@MainActor
enum WidgetPublisher {
    static let quizSize = 8
    static let wordCount = 12
    private static let upcomingWindow: TimeInterval = 3 * 86_400

    /// Records VERO/FALSO answers that were given in the widget since the app last ran.
    static func importAnswers() {
        let pending = WidgetQuizState.drain()
        guard !pending.isEmpty else { return }
        for question in ContentStore.shared.questions(ids: pending.keys.sorted()) {
            if let answer = pending[question.id] { ProgressStore.shared.record(question, answer: answer) }
        }
    }

    static func publish() {
        guard WidgetShared.container != nil, ContentStore.shared.loadError == nil else { return }
        let snapshot = makeSnapshot()
        writeImages(for: snapshot.quiz)
        WidgetShared.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func makeSnapshot(now: Date = .now) -> WidgetSnapshot {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        let preferences = Preferences.shared
        let language = preferences.helperLanguage

        var dueNow = WidgetSnapshot.ReviewCounts()
        var upcoming: [WidgetSnapshot.Upcoming] = []
        func track(_ kind: WidgetSnapshot.ReviewKind, _ due: Date) {
            if due <= now {
                dueNow.add(kind)
            } else if due <= now.addingTimeInterval(upcomingWindow) {
                upcoming.append(.init(kind: kind, due: due))
            }
        }
        for (id, card) in progress.cards {
            if id.hasPrefix("w:") { track(.word, card.due) } else if id.hasPrefix("f:") { track(.fact, card.due) }
        }
        for stat in progress.stats.values { track(.question, stat.reviewDue) }
        upcoming.sort { $0.due < $1.due }

        let recent = progress.stats.values.sorted { $0.lastAt > $1.lastAt }.prefix(100)

        return WidgetSnapshot(
            generated: now,
            helperLanguage: language.rawValue,
            showsTranslations: preferences.showsTranslations,
            dueNow: dueNow,
            upcoming: upcoming,
            mastered: progress.stats.values.filter(\.lastCorrect).count,
            questionCount: content.questionCount,
            recentAccuracy: progress.recentAccuracy,
            recentAnswers: recent.count,
            wordsLearned: progress.learnedCount(prefix: "w:"),
            exams: progress.exams.prefix(5).map { .init(date: $0.date, errors: $0.errors, maxErrors: $0.maxErrors) },
            focus: focus(language: language),
            week: progress.activity.map { $0.questions + $0.cards },
            streak: progress.streakDays(),
            studiedToday: (progress.activity.last.map { $0.questions + $0.cards } ?? 0) > 0,
            quiz: quizDeck(language: language, now: now),
            words: wordDeck(language: language),
            examQuestions: content.examRules.questionCount,
            examMaxErrors: content.examRules.maxErrors)
    }

    /// The chapter with the most open mistakes, or the next chapter to learn.
    private static func focus(language: HelperLanguage) -> WidgetSnapshot.Focus? {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        var ranked: (chapter: Chapter, summary: ProgressStore.ChapterSummary)?
        for chapter in content.chapters {
            let summary = progress.summary(chapter: chapter.id)
            // Ties go to the earlier chapter.
            if summary.mistakes > (ranked?.summary.mistakes ?? 0) { ranked = (chapter, summary) }
        }
        if let (chapter, summary) = ranked {
            return .init(chapterID: chapter.id, position: chapter.position, titleIT: chapter.shortIT,
                         titleHelper: chapter.shortTitle(language), reason: .mistakes, mistakes: summary.mistakes,
                         answered: summary.answered, total: chapter.questionCount)
        }
        guard let chapter = SessionBuilder.nextLearnQuizChapter() else { return nil }
        let summary = progress.summary(chapter: chapter.id)
        return .init(chapterID: chapter.id, position: chapter.position, titleIT: chapter.shortIT,
                     titleHelper: chapter.shortTitle(language), reason: .next, mistakes: 0,
                     answered: summary.answered, total: chapter.questionCount)
    }

    /// Open mistakes come first, then other due statements, then short new ones from the
    /// chapter being learned, so a glance at the widget is useful practice.
    private static func quizDeck(language: HelperLanguage, now: Date) -> [WidgetSnapshot.QuizItem] {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        let due = progress.dueQuestionIDs
        let mistakes = due.filter { progress.stats[$0]?.isMistake == true }
        let reviews = due.filter { progress.stats[$0]?.isMistake != true }
        var ids = Array((mistakes.prefix(quizSize / 2) + reviews.prefix(quizSize)).prefix(quizSize))
        if ids.count < quizSize {
            let chapter = SessionBuilder.nextLearnQuizChapter()?.id
            let pool = chapter.map { content.questions(chapter: $0) } ?? content.studyQuestions().shuffled()
            let fresh = pool.filter { progress.stats[$0.id] == nil && $0.textIT.count <= 150 && !ids.contains($0.id) }
            ids += fresh.shuffled().prefix(quizSize - ids.count).map(\.id)
        }
        return content.questions(ids: ids).map { question in
            .init(id: question.id, textIT: question.textIT, textHelper: question.text(language),
                  answer: question.answer, image: question.image, isMistake: progress.stats[question.id]?.isMistake == true)
        }
    }

    /// Due words first, then the next words on the ladder. Meanings stay in the helper
    /// language only; a word without one shows no meaning rather than another language.
    private static func wordDeck(language: HelperLanguage) -> [WidgetSnapshot.WordItem] {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        let dueIDs = progress.dueCardIDs(prefix: "w:").prefix(wordCount).compactMap { Int($0.dropFirst(2)) }
        var words = content.words(ids: Array(dueIDs))
        if words.count < wordCount {
            let next = content.rankedWords(limit: 400).filter { progress.cards[$0.cardID] == nil }
            words += next.prefix(wordCount - words.count)
        }
        let due = Set(dueIDs)
        return words.map { word in
            .init(id: word.id, lemma: word.lemma, partOfSpeech: word.partOfSpeech,
                  meaning: word.meaning(language, cached: progress.gloss(word: word.id, language: language)),
                  example: word.exampleIT, isDue: due.contains(word.id))
        }
    }

    /// Widgets cannot read the app bundle, so pictures are copied as small thumbnails.
    private static func writeImages(for quiz: [WidgetSnapshot.QuizItem]) {
        guard let folder = WidgetShared.imagesFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let names = Set(quiz.compactMap(\.image).map { ($0 as NSString).lastPathComponent })
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for stale in existing where !names.contains(stale) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale))
        }
        for name in names where !existing.contains(name) {
            guard let image = QuizImage.load(name), let url = WidgetShared.imageURL(name) else { continue }
            let scale = min(1, 320 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            try? thumbnail.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
        }
    }
}

/// What a widget tap opens: a full-screen session, or a detail sheet.
enum WidgetDestination: Identifiable {
    case session(StudySession)
    case statement(Question)
    case word(Word)

    var id: String {
        switch self {
        case .session(let session): "session-\(String(describing: session))"
        case .statement(let question): "statement-\(question.id)"
        case .word(let word): "word-\(word.id)"
        }
    }
}

extension WidgetLink {
    @MainActor
    var destination: WidgetDestination? {
        let content = ContentStore.shared
        switch self {
        case .review: return .session(.review)
        case .exam: return .session(.exam)
        case .words: return .session(.words(.ladder))
        case .quiz: return .session(.practice(.quickMix))
        case .learn(let chapter): return .session(.learnQuiz(chapter: chapter))
        case .chapterMistakes(let chapter): return .session(.practice(.chapterMistakes(chapter)))
        case .word(let id): return content.word(id).map(WidgetDestination.word)
        case .statement(let id, let answered, let then):
            if answered { return content.question(id).map(WidgetDestination.statement) }
            return .session(.practice(.statements([id] + then)))
        }
    }
}
