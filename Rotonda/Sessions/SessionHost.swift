import SwiftUI

enum SessionItem: Identifiable, Hashable {
    /// Answer VERO/FALSO.
    case question(Question)
    /// Learn step: the statement with its answer and explanation, nothing to answer.
    case study(Question)
    case word(Word)
    case wordChoice(Word, options: [Word])
    case fact(Fact)
    case factChoice(Fact, options: [String])

    var id: String {
        switch self {
        case .question(let question): "q\(question.id)"
        case .study(let question): "s\(question.id)"
        case .word(let word): word.cardID
        case .wordChoice(let word, _): "c\(word.cardID)"
        case .fact(let fact): fact.cardID
        case .factChoice(let fact, _): "c\(fact.cardID)"
        }
    }

    /// Learn steps don't count toward the score.
    var isGraded: Bool {
        if case .study = self { false } else { true }
    }
}

/// Picks the right full-screen experience for a session.
struct SessionHost: View {
    let session: StudySession

    var body: some View {
        switch session {
        case .read(let chapter):
            ReaderSessionView(chapterID: chapter)
        case .listen(let source):
            ListenSessionView(source: source)
        case .exam:
            ExamSessionView()
        case .examReview(let id):
            ExamReviewSessionView(examID: id)
        default:
            SessionRunnerView(session: session)
        }
    }
}

@MainActor
enum SessionBuilder {
    static let learnBatch = 5

    static func items(for session: StudySession) -> [SessionItem] {
        let length = Preferences.shared.sessionLength
        switch session {
        case .learnQuiz(let chapter):
            return learnQuiz(chapter: chapter, count: length)
        case .practice(let source):
            return questions(for: source, count: length).map(SessionItem.question)
        case .words(let source):
            return words(for: source, count: length).map(SessionItem.word)
        case .wordQuiz(let source):
            return wordQuiz(for: source, count: length)
        case .facts(let source):
            return facts(for: source, count: length).map(SessionItem.fact)
        case .numberQuiz(let source):
            return numberQuiz(for: source, count: length)
        case .review:
            return review(count: length)
        default:
            return []
        }
    }

    static func learnQuizKey(_ chapter: Int) -> String { "learnquiz-\(chapter)" }

    /// Answered statements count toward coverage even when practiced outside Learn & quiz.
    static func learnQuizDone(_ chapter: Chapter) -> Int {
        ProgressStore.shared.summary(chapter: chapter.id).answered
    }

    /// Explore chapters in book order before returning to chapters with due reviews.
    static func nextLearnQuizChapter() -> Chapter? {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        return content.chapters.first { learnQuizDone($0) < $0.questionCount }
            ?? progress.dueQuestionIDs.first.flatMap { content.question($0) }.flatMap { content.chapter($0.chapterID) }
    }

    /// Study and then test each new batch; due statements use the same learning flow.
    static func learnQuiz(chapter: Int, count: Int) -> [SessionItem] {
        let next = scheduledQuestions(ContentStore.shared.questions(chapter: chapter), count: count)
        return stride(from: 0, to: next.count, by: learnBatch).flatMap { start -> [SessionItem] in
            let batch = Array(next[start..<min(start + learnBatch, next.count)])
            return batch.map(SessionItem.study) + batch.shuffled().map(SessionItem.question)
        }
    }

    static func scheduledQuestions(_ pool: [Question], count: Int) -> [Question] {
        StudySchedule.select(pool, count: count) { ProgressStore.shared.stats[$0.id]?.reviewDue }
    }

    static func scheduledCards<Item>(_ pool: [Item], count: Int, cardID: (Item) -> String) -> [Item] {
        StudySchedule.select(pool, count: count) { ProgressStore.shared.cards[cardID($0)]?.due }
    }

    static func wordPool(for source: WordSource) -> [Word] {
        let content = ContentStore.shared
        switch source {
        case .ladder: return content.rankedWords(limit: content.wordCount)
        case .chapter(let id): return content.chapterWords(id, limit: content.wordCount)
        case .examLanguage: return content.words(kind: .exam)
        case .reach: return content.words(ids: WordReach.nextWordIDs(limit: 200))
        case .mistakes: return content.words(ids: WordReach.mistakeWordIDs())
        }
    }

    /// Meaning multiple choice follows the same discovery and review order as flashcards.
    static func wordQuiz(for source: WordSource, count: Int) -> [SessionItem] {
        let pool = wordPool(for: source).filter { !helperGloss($0).isEmpty }
        let distractors = ContentStore.shared.rankedWords(limit: 800).filter { !helperGloss($0).isEmpty }
        return scheduledCards(pool, count: count, cardID: { $0.cardID }).map { word in
            let gloss = helperGloss(word)
            var options = distractors.filter { $0.id != word.id && helperGloss($0) != gloss }
                .filter { word.partOfSpeech.isEmpty || $0.partOfSpeech == word.partOfSpeech }
                .shuffled().prefix(3)
            if options.count < 3 {
                options += distractors.filter { $0.id != word.id && helperGloss($0) != gloss }.shuffled().prefix(3 - options.count)
            }
            return .wordChoice(word, options: (Array(options) + [word]).shuffled())
        }
    }

    /// "Which number?" multiple choice. Wrong options share the unit (km/h, kg, anni…).
    static func numberQuiz(for source: FactSource, count: Int) -> [SessionItem] {
        let all = ContentStore.shared.allFacts.filter { !$0.value.isEmpty }
        let pool = factPool(for: source).filter { !$0.value.isEmpty }
        func unit(_ value: String) -> String { value.filter(\.isLetter).lowercased() }
        return scheduledCards(pool, count: count, cardID: { $0.cardID }).map { fact in
            let others = Array(Set(all.map(\.value).filter { $0 != fact.value }))
            var options = others.filter { unit($0) == unit(fact.value) }.shuffled().prefix(3)
            // Too few real values in that unit: nearby numbers in the same unit, never another unit.
            if options.count < 3 { options += nearbyValues(fact.value).filter { !options.contains($0) }.shuffled().prefix(3 - options.count) }
            if options.count < 3 { options += others.filter { !options.contains($0) }.shuffled().prefix(3 - options.count) }
            return .factChoice(fact, options: (Array(options) + [fact.value]).shuffled())
        }
    }

    /// Plausible wrong answers for "15 punti": the same text with a nearby number.
    static func nearbyValues(_ value: String) -> [String] {
        guard let range = value.range(of: #"\d+"#, options: .regularExpression), let number = Int(value[range]) else { return [] }
        let candidates = [number * 2, number / 2, number + 5, number - 5, number + 10, number + 1, number - 1]
        return Set(candidates.filter { $0 > 0 && $0 != number }).map { value.replacingCharacters(in: range, with: String($0)) }
    }

    /// Choice quizzes only use meanings available in the selected helper language.
    static func helperGloss(_ word: Word) -> String {
        let language = Preferences.shared.helperLanguage
        return word.meaning(language, cached: ProgressStore.shared.gloss(word: word.id, language: language)) ?? ""
    }

    static func questions(for source: QuestionSource, count: Int) -> [Question] {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        switch source {
        case .chapter(let id):
            return scheduledQuestions(content.questions(chapter: id), count: count)
        case .chapterMistakes(let id):
            return content.questions(ids: Array(progress.mistakeIDs(chapter: id).prefix(max(count, 20))))
        case .mistakes:
            return content.questions(ids: Array(progress.mistakeIDs.prefix(max(count, 20))))
        case .quickMix:
            return scheduledQuestions(content.studyQuestions().shuffled(), count: count)
        case .bookmarks:
            return content.questions(ids: Array(progress.bookmarks).sorted())
        case .word(let id):
            return scheduledQuestions(content.questions(ids: content.questionIDs(word: id)).shuffled(), count: count)
        case .fact(let id):
            return scheduledQuestions(content.questions(ids: content.questionIDs(fact: id)).shuffled(), count: count)
        case .group(let id):
            return scheduledQuestions(content.questions(group: id).shuffled(), count: count)
        case .picture(let image, let chapter):
            return scheduledQuestions(content.questions(image: image, chapter: chapter).shuffled(), count: count)
        case .statements(let ids):
            return content.questions(ids: ids)
        case .signs:
            return scheduledQuestions(content.studyQuestions(withImagesOnly: true).shuffled(), count: count)
        }
    }

    /// Explore unfamiliar words before their scheduled reviews.
    static func words(for source: WordSource, count: Int) -> [Word] {
        scheduledCards(wordPool(for: source), count: count, cardID: { $0.cardID })
    }

    static func factPool(for source: FactSource) -> [Fact] {
        let content = ContentStore.shared
        switch source {
        case .due: return content.allFacts
        case .deck(let deck): return content.facts(deck: deck)
        case .chapter(let id): return content.facts(chapter: id)
        }
    }

    static func facts(for source: FactSource, count: Int) -> [Fact] {
        // The explicit Due deck is review-only; deck and chapter study explore first.
        if case .due = source {
            return Array(ProgressStore.shared.dueCardIDs(prefix: "f:")
                .compactMap { ContentStore.shared.fact(String($0.dropFirst(2))) }.prefix(count))
        }
        return scheduledCards(factPool(for: source), count: count, cardID: { $0.cardID })
    }

    /// Explicit review contains due words, facts and questions, capped at the session length.
    static func review(count: Int) -> [SessionItem] {
        let content = ContentStore.shared
        let progress = ProgressStore.shared
        let words = content.words(ids: progress.dueCardIDs(prefix: "w:").prefix(count).compactMap { Int($0.dropFirst(2)) }).map(SessionItem.word)
        let facts = facts(for: .due, count: count).map(SessionItem.fact)
        let questions = content.questions(ids: Array(progress.dueQuestionIDs.prefix(count))).map(SessionItem.question)
        var result: [SessionItem] = []
        for index in 0..<max(words.count, facts.count, questions.count) {
            for list in [words, facts, questions] where index < list.count { result.append(list[index]) }
        }
        return Array(result.prefix(count))
    }
}

/// Shared top bar for full-screen sessions: close, title, progress.
struct SessionTopBar<Title: View>: View {
    let title: Title
    let position: Int
    let total: Int
    /// Makes the counter a button, for jumping to any page of a long session.
    var openJumpList: (() -> Void)? = nil
    var close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                title.font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 108)
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                            .background(Color.card, in: Circle())
                    }
                    .accessibilityLabel(Text("Close"))
                    Spacer(minLength: 0)
                    // The session's one translation toggle, beside the counter.
                    TranslationVisibilityButton()
                    let counter = Text("\(min(position, total))/\(total)")
                        .font(.subheadline.monospacedDigit())
                    if let openJumpList {
                        Button(action: openJumpList) {
                            counter.lineLimit(1).fixedSize()
                                .frame(minWidth: 60, minHeight: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text("Go to"))
                        .accessibilityValue(counter)
                    } else {
                        counter.foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize()
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
            }
            ThinProgressBar(value: total == 0 ? 0 : Double(position) / Double(total), height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .readableWidth()
    }
}

/// Closes a full-screen session with the gestures sheets and pushed screens have: pull the top
/// bar down, or swipe in from the left edge. The screen follows the finger over the app below
/// (the cover's background is clear) and closes past the threshold, like the ✕.
struct SwipeToClose: ViewModifier {
    /// Whether a swipe in from the left edge closes; off while a pager can swipe back.
    var fromEdge = true
    let close: () -> Void

    private enum Track { case undecided, down, right, ignored }
    @State private var track = Track.undecided
    @State private var offset = CGSize.zero
    @State private var frame = CGRect.zero

    /// Narrower than the cards' 16 pt margin, so it never starts a card swipe.
    private let edge: CGFloat = 16
    /// The session top bar: close button, title and progress.
    private let topBar: CGFloat = 72
    private let threshold: CGFloat = 110

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if offset == .zero { frame = $0 } }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10, coordinateSpace: .global)
                    .onChanged { value in
                        let t = value.translation
                        if track == .undecided {
                            let start = value.startLocation
                            if fromEdge && start.x < frame.minX + edge && t.width > abs(t.height) { track = .right }
                            else if start.y < frame.minY + topBar && t.height > abs(t.width) { track = .down }
                            else { track = .ignored }
                        }
                        switch track {
                        case .right: offset = CGSize(width: max(0, t.width), height: 0)
                        case .down: offset = CGSize(width: 0, height: max(0, t.height))
                        default: break
                        }
                    }
                    .onEnded { value in
                        defer { track = .undecided }
                        let distance: CGFloat, predicted: CGFloat, away: CGSize
                        switch track {
                        case .right: (distance, predicted, away) = (value.translation.width, value.predictedEndTranslation.width, CGSize(width: frame.maxX, height: 0))
                        case .down: (distance, predicted, away) = (value.translation.height, value.predictedEndTranslation.height, CGSize(width: 0, height: frame.maxY))
                        default: return
                        }
                        guard distance > threshold || predicted > threshold * 3 else {
                            withAnimation(.snappy) { offset = .zero }
                            return
                        }
                        withAnimation(.easeOut(duration: 0.2)) { offset = away } completion: {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction, close)
                        }
                    }
            )
    }
}

extension View {
    func swipeToClose(fromEdge: Bool = true, perform close: @escaping () -> Void) -> some View {
        modifier(SwipeToClose(fromEdge: fromEdge, close: close))
    }
}

/// Runs a list of mixed items (questions, learn steps, cards, choice quizzes). Every answer
/// is saved the moment it is given, so closing mid-way (the train arrives) loses nothing.
/// Cards sit in a native horizontal pager, each scrolling vertically on its own, so a drag
/// moves one axis only. The pager reaches as far as the learner has got: answering a card
/// (or reading a learn step) opens the next one, and finished cards can be swiped back to.
struct SessionRunnerView: View {
    let session: StudySession

    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    /// Built once when the session opens; rebuilding on every answer would reshuffle it.
    @State private var items: [SessionItem]?
    /// The card in view; `items.count` is the summary.
    @State private var position: Int? = 0
    /// The furthest card the pager reaches.
    @State private var unlocked = 0
    /// The first card that can be swiped back to; graded flashcards stay behind it.
    @State private var firstPage = 0
    @State private var completed: Set<Int> = []
    @State private var good = 0
    @State private var missed: [SessionItem] = []
    /// Answers given so far by position, so a card swiped back to shows its feedback again.
    @State private var answers: [Int: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            SessionTopBar(title: SessionTitle(session: session), position: min(position ?? 0, items?.count ?? 0),
                          total: items?.count ?? 0) {
                SpeechController.shared.stop()
                dismiss()
            }
            if let items {
                if items.isEmpty {
                    ContentUnavailableView("Nothing to do here right now", systemImage: "checkmark.circle",
                                           description: Text("Everything in this set is reviewed. Come back later or pick another set."))
                    Button("Close") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(16)
                } else {
                    pager(items)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .readableWidth()
        .pagerEdgeButtons(canGoBack: items?.isEmpty == false && (position ?? 0) > firstPage,
                          canGoForward: items?.isEmpty == false && (position ?? 0) < unlocked,
                          back: { go(to: (position ?? 0) - 1) }, forward: { go(to: (position ?? 0) + 1) })
        .screenBackground()
        // From the left edge only where there is no card to swipe back to.
        .swipeToClose(fromEdge: (position ?? 0) <= firstPage) {
            SpeechController.shared.stop()
            dismiss()
        }
        .onAppear { if items == nil { items = SessionBuilder.items(for: session) } }
        .onChange(of: position) { SpeechController.shared.stop() }
    }

    /// Pages from the first revisitable card to the furthest unlocked one. An ungraded
    /// flashcard stands alone, so its own Again / Got it swipe has the drag to itself.
    private func pages(_ items: [SessionItem]) -> ClosedRange<Int> {
        let current = position ?? 0
        if current < items.count, items[current].isFlashcard, !completed.contains(current) {
            return current...current
        }
        return firstPage...max(firstPage, min(unlocked, items.count))
    }

    private func pager(_ items: [SessionItem]) -> some View {
        let range = pages(items)
        return GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(range), id: \.self) { index in
                        Group {
                            if index < items.count {
                                itemView(items[index], at: index)
                            } else {
                                SessionSummaryView(good: good, total: items.filter(\.isGraded).count, missed: missed) { dismiss() }
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $position)
            .scrollIndicators(.hidden)
            .scrollDisabled(range.count < 2)
        }
    }

    @ViewBuilder private func itemView(_ item: SessionItem, at index: Int) -> some View {
        let back: (() -> Void)? = index > firstPage ? { go(to: index - 1) } : nil
        let next: () -> Void = { go(to: index + 1) }
        switch item {
        case .question(let question):
            PracticeQuestionView(question: question, answered: answers[index].map { $0 == 1 }, onBack: back,
                                 onChosen: { value in
                                     answers[index] = value ? 1 : 0
                                     complete(index, success: value == question.answer)
                                 },
                                 onFinished: { _ in next() })
        case .study(let question):
            StudyQuestionView(question: question, onBack: back, onNext: next)
                .onAppear { complete(index, success: true) }
        case .word(let word):
            WordFlashcardView(word: word) { known in graded(index, known: known) }
        case .wordChoice(let word, let options):
            WordChoiceView(word: word, options: options, answered: answers[index], onBack: back,
                           onChosen: { choice in
                               answers[index] = choice
                               complete(index, success: options.indices.contains(choice) && options[choice] == word)
                           },
                           onFinished: { _ in next() })
        case .fact(let fact):
            FactFlashcardView(fact: fact, showsDeck: session.factDeck == nil) { known in graded(index, known: known) }
        case .factChoice(let fact, let options):
            FactChoiceView(fact: fact, options: options, answered: answers[index], onBack: back,
                           showsDeck: session.factDeck == nil,
                           onChosen: { choice in
                               answers[index] = choice
                               complete(index, success: options.indices.contains(choice) && options[choice] == fact.value)
                           },
                           onFinished: { _ in next() })
        }
    }

    /// Counts a card once, the first time it is answered (or read), and opens the next one.
    private func complete(_ index: Int, success: Bool) {
        guard let items, !completed.contains(index) else { return }
        completed.insert(index)
        let item = items[index]
        if item.isGraded {
            if success { good += 1 } else { missed.append(item) }
        }
        if case .learnQuiz(let chapter) = session, case .question(let question) = item {
            let key = SessionBuilder.learnQuizKey(chapter)
            progress.setReadingPosition(max(progress.readingPosition(key), question.position), for: key)
        }
        unlocked = max(unlocked, index + 1)
    }

    /// A flashcard has flown off: record it, keep it behind, and show the next card.
    private func graded(_ index: Int, known: Bool) {
        complete(index, success: known)
        firstPage = index + 1
        go(to: index + 1)
    }

    private func go(to index: Int) {
        guard index >= firstPage, index <= unlocked else { return }
        withAnimation(.snappy) { position = index }
    }
}

extension SessionItem {
    var isStudy: Bool { !isGraded }

    /// Word and fact cards graded Again / Got it by a throw.
    var isFlashcard: Bool {
        switch self {
        case .word, .fact: true
        default: false
        }
    }
}

struct SessionSummaryView: View {
    let good: Int
    let total: Int
    let missed: [SessionItem]
    let done: () -> Void
    @Environment(Preferences.self) private var preferences

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RingProgress(value: Double(good) / Double(max(total, 1)), tint: good == total ? .vero : .signBlue, lineWidth: 10,
                             label: "\(good)/\(total)")
                    .frame(width: 110, height: 110)
                    .padding(.top, 24)
                Text(good == total ? "Perfetto!" : good * 2 >= total ? "Bravo!" : "Si impara sbagliando")
                    .font(.title.weight(.bold))
                Text(good == total ? "Everything right." : good * 2 >= total ? "Good work — the misses will come back soon." :
                        "“You learn by making mistakes.” The misses will come back soon.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To review").font(.headline)
                        ForEach(missed) { item in
                            switch item {
                            case .question(let question), .study(let question): QuestionRow(question: question)
                            case .word(let word), .wordChoice(let word, _):
                                HStack { Text(word.lemma).font(.headline); Spacer(); GlossText(word: word, font: .subheadline) }.cardStyle(padding: 12)
                            case .fact(let fact), .factChoice(let fact, _): FactCard(fact: fact, compact: true)
                            }
                        }
                    }
                }
                Button("Done", action: done).buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
        }
    }
}
