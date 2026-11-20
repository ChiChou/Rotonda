import AppIntents
import SwiftUI
import WidgetKit

/// Answer real statements from the Home Screen: open mistakes, due reviews, then new
/// statements from the chapter being learned. Answers are recorded when the app opens.
struct QuizWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.quiz, provider: QuizProvider()) { entry in
            QuizWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vero o falso")
        .description("Answer due and new statements without opening the app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct QuizEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let item: WidgetSnapshot.QuizItem?
    let chosen: Bool?
    let nextID: Int?
    let correct: Int
    let answered: Int
    /// Unanswered statements in deck order.
    var remaining: [Int] = []
}

struct QuizProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuizEntry { Self.entry(.placeholder, answers: [:], current: nil, revealed: false) }

    func getSnapshot(in context: Context, completion: @escaping (QuizEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuizEntry>) -> Void) {
        completion(Timeline(entries: [Self.current()], policy: .never))
    }

    static func current() -> QuizEntry {
        guard let snapshot = WidgetShared.loadSnapshot() else {
            return QuizEntry(date: .now, snapshot: nil, item: nil, chosen: nil, nextID: nil, correct: 0, answered: 0)
        }
        return entry(snapshot, answers: WidgetQuizState.answers, current: WidgetQuizState.current, revealed: WidgetQuizState.revealed)
    }

    static func entry(_ snapshot: WidgetSnapshot, answers: [Int: Bool], current: Int?, revealed: Bool) -> QuizEntry {
        let deck = snapshot.quiz
        let answeredItems = deck.filter { answers[$0.id] != nil }
        let correct = answeredItems.filter { answers[$0.id] == $0.answer }.count
        let open = deck.filter { answers[$0.id] == nil }
        let item: WidgetSnapshot.QuizItem?
        if revealed, let current, let shown = deck.first(where: { $0.id == current }), answers[current] != nil {
            item = shown
        } else {
            item = open.first { $0.id == current } ?? open.first
        }
        let nextID = open.first { $0.id != item?.id }?.id
        return QuizEntry(date: .now, snapshot: snapshot, item: item, chosen: item.flatMap { answers[$0.id] },
                         nextID: nextID, correct: correct, answered: answeredItems.count, remaining: open.map(\.id))
    }
}

struct AnswerStatementIntent: AppIntent {
    static let title: LocalizedStringResource = "Answer statement"
    static let isDiscoverable = false

    @Parameter(title: "Statement") var question: Int
    @Parameter(title: "Answer") var answer: Bool

    init() {}
    init(question: Int, answer: Bool) {
        self.question = question
        self.answer = answer
    }

    func perform() async throws -> some IntentResult {
        WidgetQuizState.answer(question, answer)
        return .result()
    }
}

struct NextStatementIntent: AppIntent {
    static let title: LocalizedStringResource = "Next statement"
    static let isDiscoverable = false

    /// -1 when the deck is finished.
    @Parameter(title: "Statement") var question: Int

    init() {}
    init(question: Int?) { self.question = question ?? -1 }

    func perform() async throws -> some IntentResult {
        WidgetQuizState.advance(to: question < 0 ? nil : question)
        return .result()
    }
}

struct QuizWidgetView: View {
    let entry: QuizEntry
    @Environment(\.widgetFamily) private var family

    private var isLarge: Bool { family == .systemLarge }

    /// Opens the statement on screen in the app, full screen.
    private var link: WidgetLink {
        guard let item = entry.item else { return .quiz }
        return .statement(item.id, answered: entry.chosen != nil, then: entry.remaining.filter { $0 != item.id })
    }

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: isLarge ? 12 : 8) {
                header(snapshot)
                if let item = entry.item {
                    statement(item, snapshot: snapshot)
                    Spacer(minLength: 0)
                    controls(item)
                } else {
                    finished(snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(link.url)
        } else {
            OpenAppPrompt()
        }
    }

    private func header(_ snapshot: WidgetSnapshot) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "Vero o falso?")
                .font(.caption.weight(.bold)).foregroundStyle(Color.signBlue).widgetAccentable()
            if entry.item?.isMistake == true {
                Text("Mistake")
                    .font(.caption2.weight(.bold)).foregroundStyle(Color.falso)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.falso.opacity(0.14), in: Capsule())
            }
            Spacer(minLength: 0)
            if entry.answered > 0 {
                Text("\(entry.correct)/\(entry.answered)")
                    .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityLabel(Text("\(entry.correct) of \(entry.answered) correct"))
            }
        }
    }

    @ViewBuilder
    private func statement(_ item: WidgetSnapshot.QuizItem, snapshot: WidgetSnapshot) -> some View {
        let image = item.image.flatMap(WidgetShared.imageURL).flatMap { UIImage(contentsOfFile: $0.path) }
        let text = VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: item.textIT)
                .font(isLarge ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(isLarge ? 7 : 4)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: !isLarge)
            if isLarge, snapshot.showsTranslations, item.textHelper != item.textIT {
                Text(verbatim: item.textHelper)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(4).minimumScaleFactor(0.8)
            }
        }
        if let image {
            let picture = Image(uiImage: image).resizable().scaledToFit()
                .padding(4)
                .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(Text("Road sign or traffic diagram"))
            if isLarge {
                picture.frame(maxWidth: .infinity, maxHeight: 130)
                text
            } else {
                HStack(alignment: .top, spacing: 10) {
                    picture.frame(width: 64, height: 64)
                    text
                }
            }
        } else {
            text
        }
    }

    @ViewBuilder
    private func controls(_ item: WidgetSnapshot.QuizItem) -> some View {
        if let chosen = entry.chosen {
            let right = chosen == item.answer
            HStack(spacing: 8) {
                Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(right ? Color.vero : Color.falso)
                Text(right ? "Correct" : "Wrong").fontWeight(.semibold)
                Text(verbatim: item.answer ? "VERO" : "FALSO")
                    .font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(item.answer ? Color.vero : Color.falso, in: Capsule())
                Spacer(minLength: 0)
                Button(intent: NextStatementIntent(question: entry.nextID)) {
                    Text(entry.nextID == nil ? "Done" : "Next").fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .tint(.signBlue)
            }
            .font(.subheadline)
        } else {
            HStack(spacing: 8) {
                answerButton(item, true)
                answerButton(item, false)
            }
        }
    }

    private func answerButton(_ item: WidgetSnapshot.QuizItem, _ value: Bool) -> some View {
        Button(intent: AnswerStatementIntent(question: item.id, answer: value)) {
            Text(verbatim: value ? "VERO" : "FALSO")
                .font(.subheadline.weight(.heavy))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(value ? .vero : .falso)
        .widgetAccentable()
    }

    private func finished(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text("\(entry.correct) of \(entry.answered) correct")
                .font(isLarge ? .title2.weight(.bold) : .headline).monospacedDigit()
            Text("Open Rotonda for new statements")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
