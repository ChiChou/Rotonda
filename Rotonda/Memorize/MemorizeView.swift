import SwiftUI

/// Spaced repetition for the three things a foreign learner must carry in their head:
/// the words, the numbers & rules, and the statements they got wrong.
struct MemorizeView: View {
    static let allWords = "all-words"
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions
    @Environment(Preferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let content = ContentStore.shared
        let dueWords = progress.dueCardIDs(prefix: "w:").count
        let dueFacts = progress.dueCardIDs(prefix: "f:").count
        let questions = progress.dueQuestionIDs.count
        let mistakes = progress.mistakeIDs.count
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if dueWords + dueFacts + questions > 0 {
                Card(padding: 12) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Due now").font(.subheadline.weight(.semibold))
                            Text("\(dueWords) words, \(dueFacts) facts, \(questions) questions")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Review") { sessions.start(.review) }
                            .font(.subheadline.weight(.semibold))
                            .glassButtonStyle(prominent: true)
                            .buttonBorderShape(.capsule)
                            .frame(minHeight: 44)
                            .accessibilityLabel(Text("Review all"))
                    }
                }
                }

                SectionTitle(title: "Words")
                Card(padding: 12) {
                    WordLadderSummary()
                    Divider()
                    let examWords = content.words(kind: .exam)
                    SplitLink(id: "exam-words", inCard: true) { WordListView(title: Text("Exam language"), words: examWords, showsKind: false) } label: {
                        FeatureRow(icon: "exclamationmark.bubble.fill", tint: .amberInk, title: "Exam language",
                                   subtitle: Text("\(progress.learnedCount(examWords.map(\.cardID))) of \(examWords.count) learned"))
                    }
                    Divider()
                    SplitLink(id: Self.allWords, inCard: true) { WordBrowserView() } label: {
                        FeatureRow(icon: "character.textbox", tint: .signBlue, title: "All words",
                                   subtitle: Text(content.wordCount, format: .number))
                    }
                    Divider()
                    SplitLink(id: "saved-words", inCard: true) { SavedWordsView() } label: {
                        FeatureRow(icon: "star.fill", tint: .amberInk, title: "Saved words",
                                   subtitle: Text(progress.savedWords.count, format: .number))
                    }
                }
                .buttonStyle(RowButtonStyle())

                SectionTitle(title: "Numbers & rules")
                Card(padding: 12) {
                    ForEach(FactDeck.allCases) { deck in
                        let facts = content.facts(deck: deck)
                        SplitLink(id: deck, inCard: true) { FactListView(title: Text(deck.title), facts: facts, deck: deck) } label: {
                            FeatureRow(icon: deck.icon, tint: .amberInk, title: LocalizedStringKey(Preferences.shared.string(deck.title)),
                                       subtitle: Text("\(progress.learnedCount(facts.map(\.cardID))) of \(facts.count) learned"))
                        }
                        if deck != FactDeck.allCases.last { Divider() }
                    }
                }
                .buttonStyle(RowButtonStyle())

                SectionTitle(title: "Questions")
                Card(padding: 12) {
                    // One row for mistakes: open it to read them, or quiz them straight away.
                    HStack(spacing: 12) {
                        SplitLink(id: "mistakes", inCard: true) { QuestionListView(title: Text("Mistakes"), ids: progress.mistakeIDs) } label: {
                            FeatureRow(icon: "exclamationmark.circle.fill", tint: .falso, title: "Mistakes",
                                       subtitle: Text("\(mistakes) to clear")) { EmptyView() }
                        }
                        .buttonStyle(RowButtonStyle())
                        Button("Quiz") { sessions.start(.practice(.mistakes)) }
                            .glassButtonStyle()
                            .tint(.falso)
                            .frame(minHeight: 44)
                            .accessibilityLabel(Text("Quiz mistakes"))
                    }
                    .disabled(mistakes == 0)
                    Divider()
                    SplitLink(id: "saved-questions", inCard: true) { QuestionListView(title: Text("Saved"), ids: Array(progress.bookmarks).sorted(), removesBookmarks: true) } label: {
                        FeatureRow(icon: "bookmark.fill", tint: .signBlue, title: "Saved questions",
                                   subtitle: Text(progress.bookmarks.count, format: .number))
                    }
                    if ContentStore.shared.hasPictures {
                        Divider()
                        SplitLink(id: "signs", inCard: true) { SignsGalleryView(chapter: nil) } label: {
                            FeatureRow(icon: "photo.on.rectangle.angled", tint: .falso, title: "All signs & pictures")
                        }
                    }
                }
                .buttonStyle(RowButtonStyle())
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Memorize")
        .toolbarTitleDisplayMode(.inline)
        .profileToolbar()
    }
}

/// The "top N words" ladder: an honest finish line for vocabulary.
private struct WordLadderSummary: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions

    var body: some View {
        let learned = progress.learnedCount(prefix: "w:")
        let step = [100, 250, 500, 1000, 2000].first { $0 > learned } ?? 2000
        // The whole row starts the ladder, like the quick quiz rows.
        Button { sessions.start(.words(.ladder)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Key word ladder").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(learned)/\(step)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ThinProgressBar(value: Double(learned) / Double(step))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(Text("Learn & review words"))
        .accessibilityValue(Text("\(learned)/\(step)"))
    }
}

/// Words starred on their pages, newest first. Swipe a row to unsave it.
struct SavedWordsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @State private var query = ""

    var body: some View {
        let words = ContentStore.shared.words(ids: progress.savedWordIDs)
        let visible = words.filter { $0.matches(query, language: preferences.helperLanguage) }
        List {
            if words.isEmpty {
                ContentUnavailableView("No saved words", systemImage: "star")
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Section {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, word in
                        SplitLink(id: word.id) { WordPagerView(title: Text("Saved words"), words: visible, start: index) } label: { WordListRow(word: word) }
                            .swipeActions {
                                Button(role: .destructive) { withAnimation { progress.toggleSavedWord(word.id) } } label: {
                                    Label("Remove", systemImage: "star.slash")
                                }
                            }
                    }
                } header: { TranslationSectionHeader(title: Text("\(visible.count) words")) }
            }
        }
        .readableListMargins()
        .studySearch(text: $query)
        .navigationTitle("Saved words")
        .translationToggle()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WordListView: View {
    let title: Text
    let words: [Word]
    /// Off when the title already names the words' kind, such as Exam language.
    var showsKind = true
    @Environment(Preferences.self) private var preferences
    @State private var query = ""

    var body: some View {
        let visible = words.filter { $0.matches(query, language: preferences.helperLanguage) }
        List {
            if visible.isEmpty { ContentUnavailableView.search(text: query) }
            Section {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, word in
                    SplitLink(id: word.id) { WordPagerView(title: title, words: visible, start: index, showsKind: showsKind) } label: { WordListRow(word: word) }
                }
            } header: { TranslationSectionHeader(title: Text("Words")) }
        }
        .readableListMargins()
        .studySearch(text: $query)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .translationToggle()
    }
}

struct WordListRow: View {
    let word: Word
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.lemma).font(.body.weight(.semibold))
                GlossText(word: word, font: .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            switch progress.status(word.cardID) {
            case .new: EmptyView()
            case .learning:
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.signBlue).font(.caption)
                    .accessibilityLabel(Text("Learning"))
            case .learned:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vero).font(.caption)
                    .accessibilityLabel(Text("Learned"))
            }
        }
    }
}

struct WordBrowserView: View {
    enum Order: String, CaseIterable, Identifiable {
        case importance, alphabetical
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .importance ? "Importance" : "A–Z" }
    }

    @Environment(Preferences.self) private var preferences
    @State private var order = Order.importance
    @State private var query = ""
    @State private var words: [Word] = []

    var body: some View {
        List {
            let words = filtered
            if words.isEmpty { ContentUnavailableView.search(text: query) }
            Section {
                ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                    SplitLink(id: word.id) { WordPagerView(title: Text("All words"), words: words, start: index) } label: { WordListRow(word: word) }
                }
            } header: { TranslationSectionHeader(title: Text("\(words.count) words")) }
        }
        .readableListMargins()
        .studySearch(text: $query)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $order) {
                        ForEach(Order.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label("Sort by", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .navigationTitle("All words")
        .translationToggle()
        .navigationBarTitleDisplayMode(.inline)
        .task { if words.isEmpty { words = ContentStore.shared.rankedWords(limit: 5000) } }
    }

    private var filtered: [Word] {
        let matching = words.filter { $0.matches(query, language: preferences.helperLanguage) }
        return order == .importance ? matching : matching.sorted { $0.lemma.localizedStandardCompare($1.lemma) == .orderedAscending }
    }
}

/// The same library serves all facts, a deck, or a chapter without another category screen.
struct FactListView: View {
    let title: Text
    let facts: [Fact]
    var deck: FactDeck? = nil
    @Environment(SessionCoordinator.self) private var sessions
    @State private var query = ""
    @State private var selectedDeck: FactDeck?
    @Environment(Preferences.self) private var preferences

    private var availableDecks: [FactDeck] {
        FactDeck.allCases.filter { deck in facts.contains { $0.deck == deck } }
    }

    private var filtered: [Fact] {
        let term = ContentStore.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return availableDecks.flatMap { deck in
            facts.filter { fact in
                fact.deck == deck && (selectedDeck == nil || fact.deck == selectedDeck) &&
                (term.isEmpty || ContentStore.fold([fact.topicIT, fact.textIT, fact.value,
                    fact.topic(preferences.helperLanguage), fact.text(preferences.helperLanguage)].joined(separator: " ")).contains(term))
            }
        }
    }

    var body: some View {
        let visible = filtered
        List {
            if availableDecks.count > 1 {
                Section {
                    Picker("Topic", selection: $selectedDeck) {
                        Text("All topics").tag(nil as FactDeck?)
                        ForEach(availableDecks) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                }
            }
            if let deck, query.isEmpty {
                Section {
                    Button("Memorize") { sessions.start(.facts(.deck(deck))) }
                }
            }
            if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(availableDecks) { category in
                    let items = visible.filter { $0.deck == category }
                    let chartIDs = FactComparisonView.coveredIDs(category)
                    let showsChart = query.isEmpty && !chartIDs.isEmpty &&
                        chartIDs.isSubset(of: Set(items.map(\.id)))
                    if !items.isEmpty {
                        Section {
                            if showsChart {
                                FactComparisonView(deck: category, facts: items, browsingFacts: visible, title: title)
                            }
                            ForEach(items.filter { !showsChart || !chartIDs.contains($0.id) }) { fact in
                                SplitLink(id: fact.id) {
                                    FactPagerView(title: title, facts: visible,
                                                  start: visible.firstIndex(of: fact) ?? 0, showsDeck: deck == nil)
                                } label: {
                                    FactLibraryRow(fact: fact)
                                }
                                .accessibilityIdentifier("fact-\(fact.id)")
                            }
                        } header: {
                            HStack {
                                Text(category.title)
                                Spacer()
                                Text("\(items.count)").monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .readableListMargins()
        .screenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !visible.isEmpty {
                TranslationToggleItem()
            }
        }
        .studySearch(text: $query)
    }
}

struct FactLibraryRow: View {
    let fact: Fact
    @Environment(Preferences.self) private var preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TranslationText(original: fact.italianHeadline, translated: fact.topic(preferences.helperLanguage))
                .font(.body)
                .lineLimit(2)
            if !fact.value.isEmpty {
                Text(fact.value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.amberInk)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Only compare explicitly related facts with the same unit; never infer a chart from mixed values.
private struct FactComparisonView: View {
    let deck: FactDeck
    let facts: [Fact]
    let browsingFacts: [Fact]
    let title: Text
    @State private var condition = 0

    static func coveredIDs(_ deck: FactDeck) -> Set<String> {
        switch deck {
        case .speed: Set([0, 1, 2, 3, 6, 7, 9, 10].map { "speed:\($0)" })
        case .licence: Set([6, 7, 8, 9].map { "licence:\($0)" })
        default: []
        }
    }

    private var entries: [(id: String, label: LocalizedStringKey)] {
        if deck == .licence {
            return [("licence:6", "Up to 50"), ("licence:7", "50–70"),
                    ("licence:8", "70–80"), ("licence:9", "Over 80")]
        }
        switch condition {
        case 1: return [("speed:6", "Motorways"), ("speed:7", "Main extra-urban")]
        case 2: return [("speed:9", "Motorways"), ("speed:10", "Main extra-urban")]
        default: return [("speed:0", "Motorways"), ("speed:1", "Main extra-urban"),
                         ("speed:2", "Secondary extra-urban"), ("speed:3", "Built-up areas")]
        }
    }

    private var maximum: Double {
        facts.filter { Self.coveredIDs(deck).contains($0.id) }.map(number).max() ?? 1
    }

    private func number(_ fact: Fact) -> Double {
        Double(fact.value.split(separator: " ").first.map(String.init) ?? "") ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(deck == .speed ? LocalizedStringKey("Cars") : LocalizedStringKey("Licence validity by age")).font(.headline)
            if deck == .speed {
                Picker("Conditions", selection: $condition) {
                    Text("Standard").tag(0)
                    Text("Rain").tag(1)
                    Text("New drivers").tag(2)
                }
                .pickerStyle(.segmented)
            }
            ForEach(entries, id: \.id) { entry in
                if let fact = facts.first(where: { $0.id == entry.id }) {
                    SplitLink(id: fact.id) {
                        FactPagerView(title: title, facts: browsingFacts,
                                      start: browsingFacts.firstIndex(of: fact) ?? 0, showsDeck: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(entry.label).foregroundStyle(.primary)
                                Spacer()
                                Text(fact.value).fontWeight(.bold).foregroundStyle(Color.amberInk)
                            }
                            .font(.subheadline)
                            GeometryReader { geometry in
                                Capsule().fill(Color.amber.opacity(0.12))
                                Capsule().fill(Color.amberInk)
                                    .frame(width: geometry.size.width * min(number(fact) / max(maximum, 1), 1))
                            }
                            .frame(height: 8)
                            .accessibilityHidden(true)
                        }
                        .padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("chart-\(fact.id)")
                }
            }
        }
        .padding(.vertical, 6)
    }
}
