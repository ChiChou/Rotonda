import SwiftUI

/// One box for "what does this mean?": Italian and the selected helper language, across words,
/// questions and facts — fully offline, with online dictionaries as an extra.
struct SearchView: View {
    /// Example searches in the helper language, next to the Italian ones.
    static func helperExamples(_ language: HelperLanguage) -> [String] {
        switch language {
        case .english: ["overtaking", "right of way"]
        case .chinese: ["超车", "优先权"]
        case .spanish: ["adelantamiento", "preferencia de paso"]
        }
    }

    @Environment(Preferences.self) private var preferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var results = ContentStore.SearchResults()
    @State private var completedQuery = ""

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                browse
            } else if completedQuery != query {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                if !results.words.isEmpty {
                    Section {
                        ForEach(results.words.prefix(12)) { word in
                            SplitLink(id: "w\(word.id)") { WordDetailView(word: word) } label: { WordListRow(word: word) }
                        }
                    } header: { Text("Words") }
                }
                if !results.facts.isEmpty {
                    Section {
                        ForEach(results.facts.prefix(8)) { fact in
                            SplitLink(id: "f\(fact.id)") {
                                FactPagerView(title: Text("Facts & numbers"), facts: Array(results.facts.prefix(8)),
                                              start: results.facts.prefix(8).firstIndex(of: fact) ?? 0)
                            } label: { FactLibraryRow(fact: fact) }
                        }
                    } header: { Text("Facts") }
                }
                if !results.questions.isEmpty {
                    Section {
                        ForEach(results.questions) { question in
                            SplitLink(id: "q\(question.id)") { QuestionDetailView(question: question) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(question.textIT).font(.subheadline).lineLimit(3)
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(question.text(preferences.helperLanguage))
                                            .font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .translationVisibility()
                                        Spacer(minLength: 0)
                                        VerdictLabel(answer: question.answer, compact: true)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        }
                    } header: {
                        Text("Questions (\(results.questions.count))")
                    }
                }
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                Section { OnlineLookupSection(query: query) }
            }
        }
        .navigationTitle("Search")
        .toolbarTitleDisplayMode(.inline)
        .profileToolbar()
        .toolbar {
            if completedQuery == query && !query.trimmingCharacters(in: .whitespaces).isEmpty && !results.isEmpty {
                TranslationToggleItem()
            }
        }
        .studySearch(text: $query)
        .task(id: "\(preferences.helperLanguage.rawValue):\(query)") {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            results = ContentStore.shared.search(query, language: preferences.helperLanguage)
            completedQuery = query
        }
    }

    @ViewBuilder private var browse: some View {
        Section("Browse") {
            SplitLink(id: "all-words") { WordBrowserView() } label: { browseLabel("All words", icon: "character.textbox", tint: .signBlue) }
            if ContentStore.shared.hasPictures {
                SplitLink(id: "signs") { SignsGalleryView(chapter: nil) } label: { browseLabel("All signs & pictures", icon: "photo.on.rectangle.angled", tint: .falso) }
            }
            SplitLink(id: "facts") { FactListView(title: Text("Facts & numbers"), facts: ContentStore.shared.allFacts) } label: {
                browseLabel("All facts & numbers", icon: "number.square", tint: .amberInk)
            }
        }
        Section("Try") {
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(["sosta", "precedenza", "130 km/h", "rimorchio"] + Self.helperExamples(preferences.helperLanguage), id: \.self) { example in
                    Button { query = example } label: {
                        Text(verbatim: example)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 10)
                            .foregroundStyle(Color.signBlue)
                            .background(Color.signBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }
    private func browseLabel(_ title: LocalizedStringKey, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

}
