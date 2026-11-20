import SwiftUI
import WidgetKit

/// One exam word at a time: due words first, then the next words on the ladder.
struct WordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.word, provider: WordProvider()) { entry in
            WordWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Word")
        .description("A key exam word, changing every hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct WordEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let word: WidgetSnapshot.WordItem?
}

struct WordProvider: TimelineProvider {
    func placeholder(in context: Context) -> WordEntry {
        WordEntry(date: .now, snapshot: .placeholder, word: WidgetSnapshot.placeholder.words.first)
    }

    func getSnapshot(in context: Context, completion: @escaping (WordEntry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        let snapshot = WidgetShared.loadSnapshot()
        completion(WordEntry(date: .now, snapshot: snapshot, word: snapshot?.words.first))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WordEntry>) -> Void) {
        let snapshot = WidgetShared.loadSnapshot()
        let words = snapshot?.words ?? []
        guard !words.isEmpty else {
            return completion(Timeline(entries: [WordEntry(date: .now, snapshot: snapshot, word: nil)], policy: .never))
        }
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: .now)?.start ?? .now
        // Hours since the snapshot was made pick the word, so the order survives reloads.
        let offset = max(0, Int(hour.timeIntervalSince(snapshot?.generated ?? hour) / 3_600))
        let entries = (0..<words.count).map { step in
            WordEntry(date: step == 0 ? .now : hour.addingTimeInterval(Double(step) * 3_600), snapshot: snapshot,
                      word: words[(offset + step) % words.count])
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WordWidgetView: View {
    let entry: WordEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let word = entry.word {
            content(word, showsMeaning: snapshot.showsTranslations)
                .widgetURL(WidgetLink.word(word.id).url)
        } else if family == .accessoryRectangular {
            Image(systemName: "character.book.closed.fill")
        } else {
            OpenAppPrompt()
        }
    }

    @ViewBuilder
    private func content(_ word: WidgetSnapshot.WordItem, showsMeaning: Bool) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: word.lemma).font(.headline).widgetAccentable()
                if showsMeaning, let meaning = word.meaning {
                    Text(verbatim: meaning).font(.caption).lineLimit(2)
                } else if !word.example.isEmpty {
                    Text(verbatim: word.example).font(.caption).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                headword(word, showsMeaning: showsMeaning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !word.example.isEmpty {
                    Example(word: word)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                headword(word, showsMeaning: showsMeaning)
                if !showsMeaning || word.meaning == nil, !word.example.isEmpty {
                    Example(word: word).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func headword(_ word: WidgetSnapshot.WordItem, showsMeaning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(word.isDue ? "Due" : "New word")
                .font(.caption.weight(.bold))
                .foregroundStyle(word.isDue ? Color.amberInk : Color.signBlue)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(verbatim: word.lemma)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(2).minimumScaleFactor(0.6)
            if !word.partOfSpeech.isEmpty {
                Text(LocalizedStringKey(word.partOfSpeech)).font(.caption).italic().foregroundStyle(.secondary)
            }
            if showsMeaning {
                if let meaning = word.meaning {
                    Text(verbatim: meaning).font(.subheadline.weight(.medium)).lineLimit(3).minimumScaleFactor(0.8)
                } else {
                    Text(verbatim: "—").font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Translation unavailable"))
                }
            }
        }
    }
}

/// The Italian example with the word in bold.
private struct Example: View {
    let word: WidgetSnapshot.WordItem

    var body: some View {
        var text = AttributedString(word.example)
        if let range = text.range(of: word.lemma, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .minimumScaleFactor(0.8)
    }
}
