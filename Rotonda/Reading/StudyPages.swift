import SwiftUI

// Browse items horizontally; scroll vertically only to read longer content.
// Supplementary material opens in a sheet.

// MARK: - Questions

/// Read a set of questions with their answers, starting on the one that was tapped.
struct QuestionPagerView: View {
    let title: Text
    let start: Int
    let load: () -> [Question]

    @State private var questions: [Question]?

    init(title: Text, start: Int = 0, load: @escaping () -> [Question]) {
        self.title = title
        self.start = start
        self.load = load
    }

    init(title: Text, questions: [Question], start: Int = 0) {
        self.init(title: title, start: start) { questions }
    }

    var body: some View {
        if let questions {
            PushedPager(title: title, items: questions, start: start, page: { QuestionPage(question: $0) },
                        jumpSearch: { $0.textIT }, jumpRow: { QuestionJumpRow(question: $0) })
        } else {
            Color.clear.screenBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .task { questions = load() }
        }
    }
}

/// A statement with its answer and, right below, why: the explanation, key words and facts.
/// Starts at the top; a long page scrolls vertically inside the pager.
struct QuestionPage: View {
    let question: Question
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuestionCard(question: question, imageHeight: 170)
            HStack {
                VerdictLabel(answer: question.answer)
                Spacer()
                Button { progress.toggleBookmark(question.id) } label: {
                    Image(systemName: progress.bookmarks.contains(question.id) ? "bookmark.fill" : "bookmark")
                }
                .glassButtonStyle().tint(.signBlue)
                .accessibilityLabel(Text("Save question"))
            }
            QuestionInsights(question: question, expanded: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Words

struct WordPagerView: View {
    let title: Text
    let words: [Word]
    var start = 0
    /// Off when the pager's title already names the words' kind, such as Exam language.
    var showsKind = true

    var body: some View {
        PushedPager(title: title, items: words, start: start, page: { WordPage(word: $0, showsKind: showsKind) },
                    jumpSearch: { "\($0.lemma) \($0.glosses.values.values.joined(separator: " "))" }, jumpRow: { WordListRow(word: $0) })
    }
}

/// The word, its meaning and example, how it behaves in the exam, and the review action.
struct WordPage: View {
    let word: Word
    var showsKind = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WordHeader(word: word, showsKind: showsKind)
            WordMeaningCard(word: word, translating: word.lemma)
            if !word.exampleIT.isEmpty { WordExampleCard(word: word) }
            WordExamCard(word: word)
            WordMemoryCard(word: word)
        }
    }
}

// MARK: - Facts

struct FactPagerView: View {
    let title: Text
    let facts: [Fact]
    var start = 0
    /// Off when the pager's title is already the facts' deck.
    var showsDeck = true

    var body: some View {
        PushedPager(title: title, items: facts, start: start, page: { FactPage(fact: $0, showsDeck: showsDeck) },
                    jumpSearch: { "\($0.italianHeadline) \($0.value)" }, jumpRow: { FactLibraryRow(fact: $0) })
    }
}

struct FactPage: View {
    let fact: Fact
    var showsDeck = true
    @Environment(SessionCoordinator.self) private var sessions
    @State private var questionIDs: [Int] = []
    @State private var showsQuestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FactCard(fact: fact, showsDeck: showsDeck)
            if !questionIDs.isEmpty {
                HStack(spacing: 12) {
                    Button { showsQuestions = true } label: {
                        Label("\(questionIDs.count) questions", systemImage: "list.bullet")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button { sessions.start(.practice(.fact(fact.id))) } label: {
                        Label("Quiz", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .vero))
                }
            }
            FactMemoryRow(fact: fact)
            Spacer(minLength: 0)
        }
        .task(id: fact.id) { questionIDs = ContentStore.shared.questionIDs(fact: fact.id) }
        .sheet(isPresented: $showsQuestions) {
            FactQuestionsSheet(ids: questionIDs)
        }
    }
}

private struct FactQuestionsSheet: View {
    let ids: [Int]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuestionPagerView(title: Text("Questions")) {
                ContentStore.shared.questions(ids: ids)
            }
            .closeToolbar { dismiss() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Signs

/// Read statements immediately, with adjacent pictures available in the same screen.
struct SignPagerView: View {
    let groups: [QuestionGroup]
    let chapter: Int?
    @Environment(SessionCoordinator.self) private var sessions
    @State private var selected: Int
    @State private var position: Int? = 0
    @State private var questions: [Question]
    @State private var positions: [String: Int] = [:]

    init(groups: [QuestionGroup], start: Int = 0, chapter: Int? = nil) {
        self.groups = groups
        self.chapter = chapter
        let initial = min(max(start, 0), max(groups.count - 1, 0))
        _selected = State(initialValue: initial)
        _questions = State(initialValue: groups.isEmpty ? [] : ContentStore.shared.questions(image: groups[initial].image, chapter: chapter))
    }

    var body: some View {
        VStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            Button { selectPicture(index) } label: {
                                QuizImage(name: group.image, maxHeight: 48)
                                    .frame(width: 62, height: 58)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(index == selected ? Color.signBlue : Color.hairline,
                                                    lineWidth: index == selected ? 3 : 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Picture \(index + 1) of \(groups.count)"))
                            .accessibilityValue(Text("\(group.questionCount) statements"))
                            .accessibilityAddTraits(index == selected ? .isSelected : [])
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
                // A horizontal scroller is greedy vertically; keep the strip to its thumbnails
                // so the statement pager below gets the remaining height.
                .fixedSize(horizontal: false, vertical: true)
                .onAppear { proxy.scrollTo(selected, anchor: .center) }
                .onChange(of: selected) {
                    withAnimation { proxy.scrollTo(selected, anchor: .center) }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    statementProgress
                    Spacer()
                    quizButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    statementProgress
                    quizButton
                }
            }
            .padding(.horizontal, 16)
            StudyPager(items: questions, position: $position) {
                QuestionPage(question: $0)
            }
            .id(selected)
        }
        .screenBackground()
        .navigationTitle("Signs & pictures")
        .translationToggle()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear { SpeechController.shared.stop() }
    }

    private var statementProgress: some View {
        Text("Statement \(min((position ?? 0) + 1, questions.count)) of \(questions.count)")
            .font(.subheadline).foregroundStyle(.secondary)
    }

    private var quizButton: some View {
        Button {
            guard groups.indices.contains(selected) else { return }
            sessions.start(.practice(.picture(image: groups[selected].image, chapter: chapter)))
        } label: { Text("Quiz") }
        .glassButtonStyle().tint(.vero)
        .disabled(questions.isEmpty)
    }

    private func selectPicture(_ index: Int) {
        guard index != selected, groups.indices.contains(index) else { return }
        SpeechController.shared.stop()
        positions[groups[selected].id] = position ?? 0
        let nextQuestions = ContentStore.shared.questions(image: groups[index].image, chapter: chapter)
        questions = nextQuestions
        position = min(positions[groups[index].id] ?? 0, max(nextQuestions.count - 1, 0))
        selected = index
    }
}
