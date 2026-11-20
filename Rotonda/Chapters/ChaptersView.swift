import SwiftUI

/// iPhone: the chapter list pushes a chapter. iPad: the list stays beside the open chapter,
/// and paging between chapters moves the selection in the list.
struct ChaptersView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Int?
    /// Changes only when a chapter is picked in the list, to close pages opened from the last one.
    @State private var detailID = 0

    var body: some View {
        if sizeClass == .compact {
            NavigationStack { ChapterListView(selection: nil) }
        } else {
            NavigationSplitView {
                ChapterListView(selection: Binding(get: { selection }, set: { chapter in
                    guard let chapter, chapter != selection else { return }
                    selection = chapter
                    detailID += 1
                }))
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
            } detail: {
                NavigationStack {
                    if let chapter = ContentStore.shared.chapter(selection ?? -1) {
                        ChapterPagerView(start: chapter, selection: $selection)
                    } else {
                        SplitPlaceholder(title: "Choose a chapter", systemImage: "signpost.right.and.left")
                    }
                }
                .id(detailID)
            }
            .onAppear {
                if selection == nil {
                    selection = SessionBuilder.nextLearnQuizChapter()?.id ?? ContentStore.shared.chapters.first?.id
                }
            }
        }
    }
}

private struct ChapterListView: View {
    /// Set in a split view: rows select the chapter shown beside the list instead of pushing it.
    let selection: Binding<Int?>?
    @Environment(Preferences.self) private var preferences
    @State private var query = ""

    var body: some View {
        let chapters = ContentStore.shared.chapters.filter { $0.matches(query, language: preferences.helperLanguage) }
        List(selection: selection) {
            if chapters.isEmpty { ContentUnavailableView.search(text: query) }
            ForEach(chapters) { chapter in
                Group {
                    if selection != nil {
                        ChapterRow(chapter: chapter).tag(chapter.id)
                    } else {
                        NavigationLink { ChapterPagerView(start: chapter) } label: {
                            ChapterRow(chapter: chapter)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 8, for: .scrollContent)
        .screenBackground()
        .studySearch(text: $query)
        .navigationTitle("Learn")
        .toolbarTitleDisplayMode(.inline)
        .profileToolbar()
    }
}

struct ChapterRow: View {
    let chapter: Chapter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize = 32.0

    var body: some View {
        let summary = progress.summary(chapter: chapter.id)
        let mastery = Double(summary.correct) / Double(max(chapter.questionCount, 1))
        let tint: Color = mastery >= 0.9 ? .vero : .signBlue
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.1))
                RingProgress(value: mastery, tint: tint, lineWidth: 3)
                Text("\(chapter.position)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            .frame(width: badgeSize, height: badgeSize)
            .accessibilityHidden(true)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.shortIT)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(chapter.shortTitle(preferences.helperLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(summary.correct)/\(chapter.questionCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Questions mastered"))
                        .accessibilityValue(Text("\(summary.correct)/\(chapter.questionCount)"))
                    if summary.mistakes > 0 {
                        // Not a Label: in a List its icon takes a wide column and squeezes the number.
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(summary.mistakes, format: .number).monospacedDigit()
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.falso)
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(summary.mistakes) mistakes"))
                    }
                }
                .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

/// Chapters side by side: swipe left or right to move to the next or previous chapter.
struct ChapterPagerView: View {
    let start: Chapter
    /// The split view's selection on iPad, so the list follows the paging.
    var external: Binding<Int?>? = nil
    @State private var local: Int?

    init(start: Chapter, selection: Binding<Int?>? = nil) {
        self.start = start
        self.external = selection
    }

    private var selection: Int? { external?.wrappedValue ?? local }

    var body: some View {
        let chapters = ContentStore.shared.chapters
        TabView(selection: Binding(get: { selection ?? start.id }, set: { chapter in
            if let external { external.wrappedValue = chapter } else { local = chapter }
        })) {
            ForEach(chapters) { chapter in
                ChapterHubView(chapter: chapter).tag(chapter.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .screenBackground()
        .navigationTitle(Text("Chapter \(ContentStore.shared.chapter(selection ?? start.id)?.position ?? 0)"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One chapter: learn & quiz it in small steps, with its words, numbers, signs and the
/// full read-through as study material, and extra practice once it's learned.
struct ChapterHubView: View {
    let chapter: Chapter

    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var words: [Word] = []
    @State private var facts: [Fact] = []

    var body: some View {
        let summary = progress.summary(chapter: chapter.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(summary)

                SectionTitle(title: "Study material")
                Card(padding: 12) {
                    studyMaterialLayout {
                        NavigationLink { WordListView(title: Text("Key words"), words: words) } label: {
                            FeatureRow(icon: "character.book.closed.fill", tint: .signBlue, title: "Key words",
                                       subtitle: Text("\(progress.learnedCount(words.map(\.cardID))) of \(words.count) learned")) { EmptyView() }
                        }
                        .buttonStyle(RowButtonStyle())
                        Button("Learn") { sessions.start(.words(.chapter(chapter.id))) }
                            .glassButtonStyle()
                            .tint(.signBlue)
                            .frame(minHeight: 44)
                            .accessibilityLabel(Text("Learn these words"))
                    }
                    if !facts.isEmpty {
                        Divider()
                        studyMaterialLayout {
                            NavigationLink { FactListView(title: Text("Key facts"), facts: facts) } label: {
                                FeatureRow(icon: "number.square.fill", tint: .amberInk, title: "Key facts",
                                           subtitle: Text("\(progress.learnedCount(facts.map(\.cardID))) of \(facts.count) learned")) { EmptyView() }
                            }
                            .buttonStyle(RowButtonStyle())
                            Button("Memorize") { sessions.start(.facts(.chapter(chapter.id))) }
                                .glassButtonStyle()
                                .tint(.amberInk)
                                .frame(minHeight: 44)
                                .accessibilityLabel(Text("Memorize facts"))
                        }
                    }
                    if chapter.imageGroupCount >= 3 {
                        Divider()
                        NavigationLink { SignsGalleryView(chapter: chapter) } label: {
                            FeatureRow(icon: "photo.on.rectangle.angled", tint: .falso, title: "Signs & pictures",
                                       subtitle: Text(chapter.imageGroupCount, format: .number))
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                    Divider()
                    Button { sessions.start(.read(chapter: chapter.id)) } label: {
                        let position = progress.readingPosition("chapter-\(chapter.id)")
                        FeatureRow(icon: "book.pages.fill", tint: .indigo, title: "Read with answers",
                                   subtitle: position > 0 ? Text("Resume at \(position + 1) of \(chapter.questionCount)")
                                                          : Text("\(chapter.questionCount) questions")) {
                            Image(systemName: "play.fill").foregroundStyle(Color.indigo)
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    Divider()
                    NavigationLink {
                        QuestionListView(title: Text("All questions"), ids: ContentStore.shared.questions(chapter: chapter.id).map(\.id))
                    } label: {
                        FeatureRow(icon: "list.bullet", tint: .secondary, title: "All questions")
                    }
                    .buttonStyle(RowButtonStyle())
                }

                SectionTitle(title: "More practice")
                Card(padding: 12) {
                    Button { sessions.start(.practice(.chapter(chapter.id))) } label: {
                        FeatureRow(icon: "checkmark.circle.fill", tint: .vero, title: "Quiz",
                                   subtitle: Text("\(preferences.sessionLength) questions")) {
                            Image(systemName: "play.fill").foregroundStyle(Color.vero)
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    Divider()
                    Button { sessions.start(.wordQuiz(.chapter(chapter.id))) } label: {
                        FeatureRow(icon: "character.textbox", tint: .teal, title: "Word quiz") {
                            Image(systemName: "play.fill").foregroundStyle(Color.teal)
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    if facts.contains(where: { !$0.value.isEmpty }) {
                        Divider()
                        Button { sessions.start(.numberQuiz(.chapter(chapter.id))) } label: {
                            FeatureRow(icon: "number.circle.fill", tint: .amberInk, title: "Numbers quiz") {
                                Image(systemName: "play.fill").foregroundStyle(Color.amberInk)
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                    Divider()
                    Button { sessions.start(.listen(.chapter(chapter.id))) } label: {
                        FeatureRow(icon: "headphones", tint: .purple, title: "Listen") {
                            Image(systemName: "play.fill").foregroundStyle(Color.purple)
                        }
                    }
                    .buttonStyle(RowButtonStyle())
                    if summary.mistakes > 0 {
                        Divider()
                        Button { sessions.start(.practice(.chapterMistakes(chapter.id))) } label: {
                            FeatureRow(icon: "exclamationmark.circle.fill", tint: .falso, title: "Fix mistakes",
                                       subtitle: Text("\(summary.mistakes) to clear")) {
                                Image(systemName: "play.fill").foregroundStyle(Color.falso)
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
                if chapter.hasMoreTopics {
                    SectionTitle(title: "Topics")
                    Card {
                        let topics = chapter.topics(preferences.helperLanguage)
                        ForEach(Array(topics.enumerated()), id: \.offset) { index, topic in
                            if index > 0 { Divider() }
                            VStack(alignment: .leading, spacing: 2) {
                                ItalianText(text: topic.italian, font: .callout)
                                Text(topic.translated).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .environment(\.alwaysShowsTranslations, true)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .screenBackground()
        .task(id: chapter.id) {
            words = ContentStore.shared.chapterWords(chapter.id, limit: 40)
            facts = ContentStore.shared.facts(chapter: chapter.id)
        }
    }

    private var studyMaterialLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    /// The chapter, how far Learn & quiz has got, and the one action that moves it on.
    private func header(_ summary: ProgressStore.ChapterSummary) -> some View {
        let done = SessionBuilder.learnQuizDone(chapter)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                SignBadge(text: "\(chapter.position)", size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    ItalianText(text: chapter.shortIT, font: .headline)
                    Text(chapter.shortTitle(preferences.helperLanguage)).font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .environment(\.alwaysShowsTranslations, true)
                Spacer(minLength: 0)
            }
            ThinProgressBar(value: Double(done) / Double(max(chapter.questionCount, 1)), tint: .indigo)
            HStack(alignment: .firstTextBaseline) {
                Text("\(done) of \(chapter.questionCount) learned")
                Spacer()
                if summary.answered > 0 {
                    Text("\(Text(Double(summary.correct) / Double(summary.answered), format: .percent.precision(.fractionLength(0)))) correct")
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button { sessions.start(.learnQuiz(chapter: chapter.id)) } label: {
                Label(done == 0 ? "Start learning" : (done >= chapter.questionCount ? "Review mistakes" : "Continue"),
                      systemImage: "graduationcap.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: .indigo))
        }
        .cardStyle()
    }
}

/// Every picture in a chapter. Tap one to see all statements about it — the fastest way to
/// learn a sign is to see everything the exam can say about it at once.
struct SignsGalleryView: View {
    let chapter: Chapter?
    @Environment(Preferences.self) private var preferences
    @State private var query = ""
    @State private var selectedChapter: Int?
    @State private var groups: [QuestionGroup] = []

    var body: some View {
        ScrollView {
            if chapter == nil {
                Picker("Chapter", selection: $selectedChapter) {
                    Text("All chapters").tag(nil as Int?)
                    ForEach(ContentStore.shared.chapters.filter { $0.imageGroupCount > 0 }) { item in
                        (Text(item.shortIT) + Text("\n" + item.shortTitle(preferences.helperLanguage)).font(.footnote))
                            .tag(Optional(item.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 16)
            }
            if groups.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    SplitLink(id: group.id) { SignPagerView(groups: groups, start: index, chapter: chapter?.id ?? selectedChapter) } label: {
                        VStack(spacing: 4) {
                            if let image = QuizImage.load(group.image) {
                                Image(uiImage: image).resizable().scaledToFit().frame(height: 76)
                            }
                            Text("\(group.questionCount) statements")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 104)
                        .padding(6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Picture \(index + 1) of \(groups.count)"))
                    .accessibilityValue(Text("\(group.questionCount) statements"))
                }
            }
            .padding(16)
            .readableWidth(ReadableWidth.wide)
        }
        .screenBackground()
        .navigationTitle("Signs & pictures")
        .navigationBarTitleDisplayMode(.inline)
        .studySearch(text: $query)
        .task(id: "\(chapter?.id ?? selectedChapter ?? -1):\(preferences.helperLanguage.rawValue):\(query)") {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            groups = ContentStore.shared.imageGroups(chapter: chapter?.id ?? selectedChapter,
                                                    matching: query, language: preferences.helperLanguage)
        }
    }
}
