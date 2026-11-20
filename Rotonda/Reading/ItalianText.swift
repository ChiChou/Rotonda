import SwiftUI
import Translation

/// Italian text where every word is a doorway: tap a word for its study card (offline),
/// or touch and hold, then drag across words, to translate a phrase with the system
/// translator. A plain sideways swipe is left free for moving between cards.
struct ItalianText: View {
    let text: String
    var font: Font = .title3.weight(.semibold)
    var allowsLookup = true
    /// The speech request that reads this text aloud; its current word is highlighted.
    var speechKey: String? = nil
    var speechPart = 0

    @State private var tokens: [Token] = []
    @State private var selection: ClosedRange<Int>?
    @State private var dragStart: Int?
    @State private var frames: [Int: CGRect] = [:]
    @State private var lookup: WordLookup?
    @State private var phrase = ""
    @State private var showsPhraseTranslation = false
    @State private var showsWordList = false
    private var speech = SpeechController.shared

    var body: some View {
        let spoken = speech.spokenRange(key: speechKey, part: speechPart)
        // Where each token starts in the text, in UTF-16 units like the synthesizer's ranges.
        let starts = tokens.reduce(into: [0]) { $0.append($0[$0.count - 1] + $1.text.utf16.count) }
        let isSpoken: (Int) -> Bool = { index in
            guard let spoken, index + 1 < starts.count else { return false }
            return starts[index] < spoken.location + spoken.length && spoken.location < starts[index + 1]
        }
        FlowLayout {
            ForEach(Array(tokens.enumerated()), id: \.offset) { index, token in
                if token.isWord && allowsLookup {
                    // An underline marks words that open a study card.
                    Text(token.text)
                        .underline(ContentStore.shared.hasWord(forForm: token.text), pattern: .solid,
                                   color: Color.secondary.opacity(0.5))
                        .font(font)
                        .background(selection?.contains(index) == true ? Color.signBlue.opacity(0.22)
                                        : isSpoken(index) ? Color.amber.opacity(0.4) : .clear,
                                    in: RoundedRectangle(cornerRadius: 3))
                        .onTapGesture { tap(index) }
                        .layoutValue(key: FlowBreak.self, value: token.flowBreak)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: TokenFrames.self, value: [index: geometry.frame(in: .named("italianText"))])
                        })
                } else {
                    Text(token.text).font(font)
                        .background(token.isWord && isSpoken(index) ? Color.amber.opacity(0.4) : .clear,
                                    in: RoundedRectangle(cornerRadius: 3))
                        .layoutValue(key: FlowBreak.self, value: token.flowBreak)
                }
            }
        }
        .coordinateSpace(name: "italianText")
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    if case .second(true, let drag?) = value { self.drag(drag) }
                }
                .onEnded { value in
                    if case .second(true, _) = value { endDrag() }
                },
            isEnabled: allowsLookup
        )
        .onPreferenceChange(TokenFrames.self) { frames = $0 }
        .onAppear { tokens = Token.split(text) }
        .onChange(of: text) { _, value in
            tokens = Token.split(value)
            selection = nil
        }
        .sheet(item: $lookup, onDismiss: { selection = nil }) { lookup in
            WordSheet(form: lookup.form)
        }
        .translationPresentation(isPresented: $showsPhraseTranslation, text: phrase)
        .onChange(of: showsPhraseTranslation) { _, showing in if !showing { selection = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityActions {
            if allowsLookup {
                Button("Look up words") { showsWordList = true }
                Button("Translate sentence") {
                    phrase = text
                    showsPhraseTranslation = true
                }
            }
        }
        .sheet(isPresented: $showsWordList) {
            CloseSheet {
                List(Array(Set(Token.split(text).filter { $0.isWord && ContentStore.shared.hasWord(forForm: $0.text) }.map(\.text))).sorted(),
                     id: \.self) { word in
                    NavigationLink {
                        if let entry = ContentStore.shared.word(forForm: word) {
                            WordDetailView(word: entry, tappedForm: word)
                        } else {
                            UnknownWordView(form: word)
                        }
                    } label: { Text(verbatim: word) }
                }
                .navigationTitle("Look up words")
            }
        }
    }

    /// Only words with a study card open one; grammar words ("di", "un") do nothing.
    private func tap(_ index: Int) {
        guard ContentStore.shared.hasWord(forForm: tokens[index].text) else { return }
        selection = index...index
        lookup = WordLookup(form: tokens[index].text)
    }

    private func drag(_ value: DragGesture.Value) {
        guard let index = frames.first(where: { $0.value.insetBy(dx: -2, dy: -4).contains(value.location) })?.key else { return }
        if dragStart == nil { dragStart = index }
        if let start = dragStart { selection = min(start, index)...max(start, index) }
    }

    private func endDrag() {
        defer { dragStart = nil }
        guard let selection else { return }
        phrase = tokens[selection].map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        showsPhraseTranslation = !phrase.isEmpty
    }

    struct Token {
        let text: String
        let isWord: Bool
        var flowBreak = FlowBreak.Value.normal

        /// Words, spaces and punctuation as separate runs. Punctuation keeps to the word it
        /// touches, so lines never end on "(" or start on ",", "un'auto" and "km/h" never split,
        /// and a space never starts a line.
        static func split(_ text: String) -> [Token] {
            enum Kind { case word, space, mark }
            func kind(_ character: Character) -> Kind {
                character.isLetter ? .word : (character.isWhitespace ? .space : .mark)
            }
            var runs: [(Kind, String)] = []
            for character in text {
                let k = kind(character)
                if let last = runs.last, last.0 == k { runs[runs.count - 1].1.append(character) }
                else { runs.append((k, String(character))) }
            }
            return runs.indices.map { index in
                let (k, run) = runs[index]
                switch k {
                case .word:
                    // "un'auto" and "km/h" stay whole: a word right after an inner mark keeps to it.
                    let joined = index > 1 && runs[index - 1].0 == .mark && runs[index - 2].0 == .word
                    return Token(text: run, isWord: true, flowBreak: joined ? .keepWithPrevious : .normal)
                case .space: return Token(text: run, isWord: false, flowBreak: .space)
                case .mark:
                    let afterWord = index > 0 && runs[index - 1].0 == .word
                    let beforeWord = index + 1 < runs.count && runs[index + 1].0 == .word
                    // "parola," keeps to the word before; " (parola" and " «parola" keep to the word after.
                    let glue: FlowBreak.Value = afterWord ? .keepWithPrevious : (beforeWord ? .keepWithNext : .normal)
                    return Token(text: run, isWord: false, flowBreak: glue)
                }
            }
        }
    }
}

struct WordLookup: Identifiable {
    let form: String
    var id: String { form }
}

private struct TokenFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Wrap at the width that was measured. The bounds hug the longest line, so re-wrapping
        // to them could break a line that just fitted and draw it outside the measured height.
        let arrangement = arrange(width: max(bounds.width, proposal.width ?? 0), subviews: subviews)
        for (subview, point) in zip(subviews, arrangement.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, used: CGFloat = 0
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let roles = subviews.map { $0[FlowBreak.self] }
        for (index, size) in sizes.enumerated() {
            let role = roles[index]
            // Glued items wrap as one: an opening mark with its word, a word with its punctuation.
            var needed = size.width, last = index
            while last + 1 < sizes.count, roles[last] == .keepWithNext || roles[last + 1] == .keepWithPrevious {
                last += 1
                needed += sizes[last].width
            }
            if x + needed > width + 0.5, x > 0, role != .keepWithPrevious, role != .space {
                x = 0
                y += lineHeight
                lineHeight = 0
            }
            if role == .space && x == 0 && index > 0 {
                // A space that would start a line is dropped.
                points.append(CGPoint(x: x, y: y))
                continue
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width
            lineHeight = max(lineHeight, size.height)
            used = max(used, min(x, width))
        }
        return (CGSize(width: min(used, width), height: y + lineHeight), points)
    }
}

/// How a flowed item may break from its neighbours.
nonisolated struct FlowBreak: LayoutValueKey {
    nonisolated enum Value { case normal, space, keepWithPrevious, keepWithNext }
    static let defaultValue = Value.normal
}

/// Shared visibility persists through navigation, paging and app launches.
struct TranslationVisibilityButton: View {
    @Environment(\.alwaysShowsTranslations) private var alwaysShowsTranslations
    @Environment(Preferences.self) private var preferences
    /// In an iPad split view, the column this button is in: while it shows, the list columns to
    /// its left drop theirs (see `TranslationToggleItem`).
    @Environment(\.splitColumn) private var column
    @State private var id = UUID()

    var body: some View {
        if !alwaysShowsTranslations {
            Button {
                preferences.showsTranslations.toggle()
            } label: {
                Image(systemName: "translate")
                    .foregroundStyle(preferences.showsTranslations ? Color.signBlue : Color.secondary)
                    .font(.subheadline.weight(.medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(preferences.showsTranslations ? Text("Hide translations") : Text("Show translations"))
            .accessibilityAddTraits(preferences.showsTranslations ? .isSelected : [])
            .accessibilityIdentifier("translationVisibility")
            .onAppear { column?.translationToggles.insert(id) }
            .onDisappear { column?.translationToggles.remove(id) }
        }
    }
}

/// The navigation bar's translation toggle. In an iPad split view a list column leaves it out
/// while the page beside it shows one, so the screen keeps a single toggle.
struct TranslationToggleItem: ToolbarContent {
    var placement: ToolbarItemPlacement = .topBarTrailing
    @Environment(\.alwaysShowsTranslations) private var alwaysShowsTranslations
    @Environment(\.splitTarget) private var target

    var body: some ToolbarContent {
        if !alwaysShowsTranslations && (target?.translationToggles.isEmpty ?? true) {
            ToolbarItem(placement: placement) { TranslationVisibilityButton() }
        }
    }
}

extension View {
    /// The screen's one translation toggle, in its navigation bar. Cards and sections never carry
    /// their own; it hides itself where translations always show.
    func translationToggle() -> some View {
        toolbar { TranslationToggleItem() }
    }
}

extension EnvironmentValues {
    /// Explicit word lookups reveal translations without changing the saved study preference.
    @Entry var alwaysShowsTranslations = false
}

/// A section title for translated content. The translation toggle is not here: each screen has
/// one, in its navigation bar or session bar (see `translationToggle()`).
struct TranslationSectionHeader: View {
    let title: Text

    var body: some View {
        HStack {
            title
            Spacer()
        }
        .textCase(nil)
    }
}

/// Keep hidden translations in layout without exposing invisible content to input or VoiceOver.
private struct TranslationVisibility: ViewModifier {
    var isTranslation = true
    @Environment(\.alwaysShowsTranslations) private var alwaysShowsTranslations
    @Environment(Preferences.self) private var preferences

    func body(content: Content) -> some View {
        let visible = !isTranslation || alwaysShowsTranslations || preferences.showsTranslations
        content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

extension View {
    func translationVisibility(isTranslation: Bool = true) -> some View {
        modifier(TranslationVisibility(isTranslation: isTranslation))
    }
}

/// An Italian line with its translation underneath, smaller and quieter. The translation
/// follows the shared setting and never replaces the Italian.
struct TranslationText: View {
    let original: String
    let translated: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: original)
                .fixedSize(horizontal: false, vertical: true)
            if !translated.isEmpty && translated != original {
                Text(verbatim: translated)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .translationVisibility()
            }
        }
    }
}

/// Helper text follows the shared setting; revealing one item reveals every item.
struct HelperTranslation: View {
    let text: String
    /// The speech request that reads this translation aloud, and which of its parts it is.
    var speechKey: String? = nil
    var speechPart = 0
    @Environment(Preferences.self) private var preferences
    private var speech = SpeechController.shared

    var body: some View {
        if !text.isEmpty {
            // Below the Italian, smaller and quieter, so the Italian stays the thing to read.
            Text(highlighted).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .translationVisibility()
        }
    }

    /// The translation with the word being spoken marked.
    private var highlighted: AttributedString {
        var attributed = AttributedString(text)
        if let spoken = speech.spokenRange(key: speechKey, part: speechPart),
           let range = Range(spoken, in: text), let marked = Range(range, in: attributed) {
            attributed[marked].backgroundColor = Color.amber.opacity(0.4)
            attributed[marked].foregroundColor = Color.primary
        }
        return attributed
    }
}

/// Lists, chips and details use the same language-specific meaning and loading path.
struct GlossText: View {
    let word: Word
    var font: Font = .title3.weight(.semibold)
    @Environment(Preferences.self) private var preferences

    var body: some View {
        LocalizedGlossText(word: word, language: preferences.helperLanguage, font: font)
            .id("\(word.id)-\(preferences.helperLanguage.rawValue)")
    }
}

/// Immutable language identity keeps an in-flight response tied to its original cache key.
private struct LocalizedGlossText: View {
    let word: Word
    let language: HelperLanguage
    let font: Font
    @Environment(ProgressStore.self) private var progress
    @State private var configuration: TranslationSession.Configuration?

    private var display: String? {
        word.meaning(language, cached: progress.gloss(word: word.id, language: language))
    }

    var body: some View {
        Group {
            if let display {
                Text(display).font(font)
            } else {
                Text(verbatim: "—").font(font).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Translation unavailable"))
            }
        }
        .translationVisibility()
        .task { await requestIfInstalled() }
        .translationTask(configuration) { [source = translationSource, wordID = word.id, language] session in
            guard let response = try? await session.translate(source), !Task.isCancelled else { return }
            await MainActor.run { ProgressStore.shared.saveGloss(response.targetText, word: wordID, language: language) }
        }
    }

    private var sourceLanguage: Locale.Language {
        // From the English meaning when there is one (a closer source than the bare lemma).
        Locale.Language(identifier: !word.glossEN.isEmpty && language != .english ? "en" : "it")
    }

    private var translationSource: String {
        !word.glossEN.isEmpty && language != .english ? word.glossEN : word.lemma
    }

    private func requestIfInstalled() async {
        guard display == nil else { return }
        let target = language.localeLanguage
        let source = sourceLanguage
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled, status == .installed else { return }
        configuration = TranslationSession.Configuration(source: source, target: target)
    }
}

/// Consistent search language and placement across study libraries.
private struct StudySearch: ViewModifier {
    @Binding var query: String
    @Environment(Preferences.self) private var preferences

    func body(content: Content) -> some View {
        content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                           prompt: Text("Italian or \(preferences.helperLanguage.nativeName)"))
    }
}

extension View {
    func studySearch(text: Binding<String>) -> some View {
        modifier(StudySearch(query: text))
    }
}
