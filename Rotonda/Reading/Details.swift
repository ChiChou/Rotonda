import SwiftUI
import Translation

// MARK: - Word

/// Shown when the learner taps any Italian word, anywhere in the app.
struct WordSheet: View {
    let form: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let word = ContentStore.shared.word(forForm: form) {
                    WordDetailView(word: word, tappedForm: form)
                } else {
                    UnknownWordView(form: form)
                }
            }
            .closeToolbar { dismiss() }
        }
        .environment(\.alwaysShowsTranslations, true)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct WordDetailView: View {
    let word: Word
    var tappedForm: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WordHeader(word: word, tappedForm: tappedForm)
                WordMeaningCard(word: word, translating: tappedForm ?? word.lemma)
                WordMemoryCard(word: word)
                if word.questionCount >= 3 { AnswerSignal(word: word) }
                WordExamplesContent(word: word)
            }
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle(word.lemma)
        .navigationBarTitleDisplayMode(.inline)
        .translationToggle()
    }
}

private struct WordExamplesContent: View {
    let word: Word
    @State private var questions: [Question] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !word.exampleIT.isEmpty { WordExampleCard(word: word) }
            questionsSection
            Card { OnlineLookupSection(query: word.lemma) }
        }
        .task(id: word.id) { questions = ContentStore.shared.questions(ids: Array(ContentStore.shared.questionIDs(word: word.id).prefix(4))) }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TranslationSectionHeader(title: Text("In the exam").font(.headline))
            ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                NavigationLink {
                    QuestionPagerView(title: Text(verbatim: word.lemma), start: index) {
                        ContentStore.shared.questions(ids: ContentStore.shared.questionIDs(word: word.id))
                    }
                } label: { QuestionRow(question: question) }
                    .buttonStyle(CardButtonStyle())
            }
            if word.questionCount > questions.count {
                NavigationLink {
                    QuestionListView(title: Text(verbatim: word.lemma), ids: ContentStore.shared.questionIDs(word: word.id))
                } label: {
                    Label("All \(word.questionCount) questions", systemImage: "list.bullet").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// The word, its tags and a pronounce button.
struct WordHeader: View {
    let word: Word
    var tappedForm: String? = nil
    var showsKind = true

    init(word: Word, tappedForm: String? = nil, showsKind: Bool = true) {
        self.word = word
        self.tappedForm = tappedForm
        self.showsKind = showsKind
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(word.lemma).font(.largeTitle.weight(.bold))
                if let tappedForm, ContentStore.normalize(tappedForm) != word.lemma {
                    Text("Seen as “\(tappedForm)”").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if showsKind && word.kind == .exam { Pill(Text("Exam language"), tint: .amberInk) }
                    if showsKind && word.kind == .road { Pill(Text("Road term"), tint: .signBlue) }
                    if !word.partOfSpeech.isEmpty { Pill(Text(LocalizedStringKey(word.partOfSpeech))) }
                    if let level = word.level { Pill(Text(verbatim: level)) }
                }
            }
            Spacer()
            ItalianSpeechButton(text: word.lemma, key: "word-\(word.id)")
            SaveWordButton(word: word)
        }
    }
}

/// A star that saves the word to the Saved words list.
struct SaveWordButton: View {
    let word: Word
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        let saved = progress.savedWords[word.id] != nil
        Button { progress.toggleSavedWord(word.id) } label: {
            Image(systemName: saved ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(saved ? Color.amber : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Save word"))
        .accessibilityAddTraits(saved ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: saved)
    }
}

struct WordMeaningCard: View {
    let word: Word
    /// What the system translator opens with: the form the learner tapped, or the word.
    let translating: String

    @Environment(Preferences.self) private var preferences
    @State private var showsSystemTranslation = false

    var body: some View {
        Card {
            TranslationSectionHeader(title: Text("Meaning").font(.caption.weight(.bold)).foregroundStyle(.secondary))
            GlossText(word: word)
            let note = word.note(preferences.helperLanguage)
            if !note.isEmpty {
                Label { Text(note) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.amber) }
                    .font(.callout).translationVisibility()
            }
            Button { showsSystemTranslation = true } label: {
                Label("System translator", systemImage: "translate").font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
        .translationPresentation(isPresented: $showsSystemTranslation, text: translating)
        // A word's page exists to give its meaning, so it shows even while translations are hidden.
        .environment(\.alwaysShowsTranslations, true)
    }
}

/// Where a word stands in spaced repetition. A word becomes "learned" only by answering it in
/// a session, so a reference page offers to queue it rather than to mark it known.
struct WordMemoryCard: View {
    let word: Word
    var body: some View { MemoryStatusView(cardID: word.cardID) }
}

/// A memory card's place in spaced repetition, shared by word and fact pages: queue a new card
/// for review, or see when it comes back and reset it.
struct MemoryStatusView: View {
    let cardID: String
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        let state = progress.cards[cardID]
        switch progress.status(cardID) {
        case .new:
            Button { progress.review(cardID, known: false) } label: {
                Label("Add to review", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        case .learning, .learned:
            HStack(spacing: 10) {
                Image(systemName: state?.isLearned == true ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(state?.isLearned == true ? Color.vero : Color.signBlue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state?.isLearned == true ? "Learned" : "Learning").font(.subheadline.weight(.semibold))
                    if let due = state?.due {
                        Text("Next review \(due, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Reset", role: .destructive) { progress.forget(cardID) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
        }
    }
}

struct WordExampleCard: View {
    let word: Word

    var body: some View {
        Card {
            Text("Example").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
            WordExampleText(word: word)
        }
    }
}

/// A word's example sentence with its translation in the helper language only.
struct WordExampleText: View {
    let word: Word
    var font: Font = .body
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItalianText(text: word.exampleIT, font: font)
            let translation = word.exampleTranslation(preferences.helperLanguage)
            if !translation.isEmpty {
                Text(translation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .translationVisibility()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How often statements containing this word are true. A study aid, not a rule.
struct AnswerSignal: View {
    let word: Word

    var body: some View {
        Card { AnswerPattern(word: word) }
    }
}

/// The word's questions, and how often they are true.
struct WordExamCard: View {
    let word: Word

    var body: some View {
        Card {
            NavigationLink {
                QuestionListView(title: Text(verbatim: word.lemma), ids: ContentStore.shared.questionIDs(word: word.id))
            } label: {
                HStack {
                    Text("In the exam").font(.headline).foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(word.questionCount) questions").foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color(UIColor.tertiaryLabel))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            if word.questionCount >= 3 { AnswerPattern(word: word) }
        }
    }
}

private struct AnswerPattern: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Answer pattern").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text("\(Int((word.trueShare * 100).rounded()))% VERO").font(.caption.weight(.bold)).monospacedDigit()
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.vero).frame(width: geometry.size.width * word.trueShare)
                    Rectangle().fill(Color.falso)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            if word.questionCount >= 8 && (word.trueShare >= 0.8 || word.trueShare <= 0.2) {
                Text(word.trueShare >= 0.8 ? "Statements with this word are usually VERO — but read the whole sentence." :
                        "Statements with this word are usually FALSO — but read the whole sentence.")
                    .font(.callout)
            }
        }
    }
}

struct UnknownWordView: View {
    let form: String
    @State private var showsTranslation = false

    init(form: String) { self.form = form }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(form).font(.largeTitle.weight(.bold))
                Text("A common grammar word. It has no study card, but you can hear it or translate it.")
                    .foregroundStyle(.secondary)
                HStack {
                    ItalianSpeechButton(text: form, key: "form-\(form)")
                    Button { showsTranslation = true } label: { Label("Translate", systemImage: "translate") }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Card { OnlineLookupSection(query: form) }
            }
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle(form)
        .navigationBarTitleDisplayMode(.inline)
        .translationPresentation(isPresented: $showsTranslation, text: form)
    }
}

// MARK: - Questions

struct QuestionRow: View {
    let question: Question
    /// In a List the row supplies its own background.
    var inList = false
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = question.image, let uiImage = QuizImage.load(image) {
                Image(uiImage: uiImage).resizable().scaledToFit()
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
            // The statement takes the full width; its verdict follows on a line of its own.
            VStack(alignment: .leading, spacing: 6) {
                Text(question.textIT).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(question.text(preferences.helperLanguage)).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .translationVisibility()
                HStack(spacing: 8) {
                    VerdictLabel(answer: question.answer, compact: true)
                    if progress.stats[question.id]?.isMistake == true {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.falso).font(.caption)
                            .accessibilityLabel(Text("In your mistakes"))
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(inList ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inList ? Color.clear : Color.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct QuestionListView: View {
    let title: Text
    let ids: [Int]
    /// Saved questions: swipe a row to unsave it.
    var removesBookmarks = false
    @Environment(ProgressStore.self) private var progress
    @Environment(Preferences.self) private var preferences
    @State private var query = ""
    @State private var questions: [Question] = []

    private var filtered: [Question] {
        let term = ContentStore.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return term.isEmpty ? questions : questions.filter {
            ContentStore.fold($0.textIT).contains(term) ||
            ContentStore.fold($0.text(preferences.helperLanguage)).contains(term)
        }
    }

    var body: some View {
        let visible = filtered
        List {
            if visible.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }
            Section {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, question in
                    SplitLink(id: question.id) { QuestionPagerView(title: title, questions: visible, start: index) } label: {
                        QuestionRow(question: question, inList: true)
                    }
                    .swipeActions {
                        if removesBookmarks {
                            Button(role: .destructive) { unsave(question) } label: {
                                Label("Remove", systemImage: "bookmark.slash")
                            }
                        }
                    }
                }
            } header: {
                TranslationSectionHeader(title: Text("\(visible.count) questions"))
            }
        }
        .readableListMargins()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .translationToggle()
        .studySearch(text: $query)
        .task { questions = ContentStore.shared.questions(ids: ids) }
    }

    private func unsave(_ question: Question) {
        if progress.bookmarks.contains(question.id) { progress.toggleBookmark(question.id) }
        withAnimation { questions.removeAll { $0.id == question.id } }
    }
}

/// Everything about one statement: picture, Italian, translation, verdict, explanation,
/// its key words and the facts it tests.
struct QuestionDetailView: View {
    let question: Question
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuestionCard(question: question)
                VerdictLabel(answer: question.answer)
                QuestionInsights(question: question, expanded: true)
            }
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .navigationTitle(Text("Question \(question.id)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            TranslationToggleItem()
            ToolbarItem(placement: .primaryAction) {
                Button { progress.toggleBookmark(question.id) } label: {
                    Image(systemName: progress.bookmarks.contains(question.id) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(Text("Save question"))
            }
        }
    }
}

/// Picture + tappable Italian + helper translation + reading tools.
struct QuestionCard: View {
    let question: Question
    var allowsLookup = true
    var imageHeight: CGFloat = 190
    /// Off when the question sits inside another card.
    var framed = true
    var textFont: Font = .title3.weight(.semibold)
    /// Off: a small picture that hugs its content, for previews such as Today's challenge.
    var imageFillsWidth = true

    @Environment(Preferences.self) private var preferences

    init(question: Question, allowsLookup: Bool = true, imageHeight: CGFloat = 190, framed: Bool = true,
         textFont: Font = .title3.weight(.semibold), imageFillsWidth: Bool = true) {
        self.question = question
        self.allowsLookup = allowsLookup
        self.imageHeight = imageHeight
        self.framed = framed
        self.textFont = textFont
        self.imageFillsWidth = imageFillsWidth
    }

    var body: some View {
        if framed {
            Card { content }
        } else {
            VStack(alignment: .leading, spacing: 12) { content }
        }
    }

    @ViewBuilder private var content: some View {
            if let image = question.image { QuizImage(name: image, maxHeight: imageHeight, fillsWidth: imageFillsWidth) }
            ItalianText(text: question.textIT, font: textFont, allowsLookup: allowsLookup, speechKey: "q-\(question.id)")
            HelperTranslation(text: question.text(preferences.helperLanguage))
                .id(question.id)
            HStack(spacing: 10) {
                ItalianSpeechButton(text: question.textIT, key: "q-\(question.id)")
                Spacer()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)
    }
}

/// Explanation, key words and linked facts for a question.
struct QuestionInsights: View {
    let question: Question
    var expanded = false

    @Environment(Preferences.self) private var preferences
    @State private var words: [Word] = []
    @State private var facts: [Fact] = []
    @State private var lookup: WordLookup?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if question.hasExplanation {
                Card {
                    HStack {
                        Label("Why", systemImage: "lightbulb.fill").font(.headline).foregroundStyle(Color.signBlue)
                        Spacer()
                    }
                    if !question.italianExplanation.isEmpty {
                        ItalianText(text: question.italianExplanation, font: .body)
                    }
                    HelperTranslation(text: question.explanation(preferences.helperLanguage))
                }
            }
            if !words.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key words").font(.headline)
                    FlowLayout {
                        ForEach(words) { word in
                            Button { lookup = WordLookup(form: word.lemma) } label: {
                                WordChip(word: word)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6).padding(.bottom, 6)
                        }
                    }
                }
            }
            ForEach(facts) { fact in FactCard(fact: fact, compact: !expanded) }
        }
        .task(id: question.id) {
            words = ContentStore.shared.words(inQuestion: question.id)
            facts = ContentStore.shared.facts(forQuestion: question.id)
        }
        .sheet(item: $lookup) { WordSheet(form: $0.form) }
    }
}

struct WordChip: View {
    let word: Word
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        HStack(spacing: 6) {
            if progress.status(word.cardID) == .learned {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vero).font(.caption)
            }
            Text(word.lemma).font(.subheadline.weight(.semibold))
            GlossText(word: word, font: .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.card, in: Capsule())
        .overlay(Capsule().stroke(Color.hairline.opacity(0.6)))
    }
}

// MARK: - Facts

struct FactCard: View {
    let fact: Fact
    var compact = false
    /// Off where the screen is already about this fact's deck, such as a Speed limits list.
    var showsDeck = true
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsDeck {
                Label { Text(fact.deck.title) } icon: { Image(systemName: fact.deck.icon) }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if compact {
                FactLibraryRow(fact: fact)
            } else {
                if !fact.value.isEmpty {
                    Text(fact.value)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(Color.amberInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if fact.deck == .contrasts {
                    FlowLayout {
                        ForEach(fact.topicIT.components(separatedBy: " / "), id: \.self) { term in
                            Text(term).font(.headline)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.trailing, 6).padding(.bottom, 6)
                        }
                    }
                } else if !fact.topicIT.isEmpty {
                    ItalianText(text: fact.topicIT, font: .headline)
                } else {
                    // A short helper title must not reserve room for the whole Italian rule.
                    Text(fact.topic(preferences.helperLanguage))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .translationVisibility()
                }
                FactPictures(fact: fact)
                if !fact.textIT.isEmpty && fact.textIT != fact.topicIT {
                    ItalianText(text: fact.textIT, font: .body)
                }
                HelperTranslation(text: fact.text(preferences.helperLanguage))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The signs a fact describes ("180 km to Florence"), from the questions that test it.
struct FactPictures: View {
    let fact: Fact
    @State private var images: [String] = []

    var body: some View {
        HStack(spacing: 10) {
            ForEach(images, id: \.self) { name in
                QuizImage(name: name, maxHeight: 96, fillsWidth: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: fact.id) { images = ContentStore.shared.images(fact: fact.id) }
    }
}

/// A single search or linked fact uses the same reader as the library.
struct FactDetailView: View {
    let fact: Fact

    var body: some View {
        FactPagerView(title: Text("Facts & numbers"), facts: [fact])
    }
}

struct FactMemoryRow: View {
    let fact: Fact
    var body: some View { MemoryStatusView(cardID: fact.cardID) }
}
