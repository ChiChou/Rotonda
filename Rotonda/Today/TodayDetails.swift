import Charts
import SwiftUI

/// Opened from Today's progress card: how much of the bank is mastered, the memory decks and
/// every chapter.
struct ProgressDetailView: View {
    @Environment(ProgressStore.self) private var progress
    @State private var sharing: StoryMoment?

    var body: some View {
        let total = ContentStore.shared.questionCount
        let mastered = progress.stats.values.filter(\.lastCorrect).count
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(progress.bankMastery, format: .percent.precision(.fractionLength(0)))
                            .font(.largeTitle.weight(.bold)).foregroundStyle(Color.signBlue)
                        Spacer()
                        Text("\(mastered) of \(total) questions").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ThinProgressBar(value: progress.bankMastery)
                    Text("Questions mastered").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                LabeledContent("Questions answered", value: "\(progress.stats.count)")
                if let accuracy = progress.recentAccuracy {
                    LabeledContent("Last 100 answers") { Text(accuracy, format: .percent.precision(.fractionLength(0))) }
                }
                LabeledContent("Mistakes") { Text("\(progress.mistakeIDs.count) to clear") }
            }
            Section {
                LabeledContent("Words learned", value: "\(progress.learnedCount(prefix: "w:"))")
                LabeledContent("Facts learned", value: "\(progress.learnedCount(prefix: "f:"))")
            }
            Section {
                ForEach(ContentStore.shared.chapters) { ChapterProgressRow(chapter: $0) }
            } header: { Text("Chapters") }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sharing = .currentProgress(progress) } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sharing) { moment in CloseSheet(detents: [.large]) { StoryShareSheet(moment: moment) } }
    }
}

/// A chapter's mastered share, with its open mistakes.
struct ChapterProgressRow: View {
    let chapter: Chapter
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        let summary = progress.summary(chapter: chapter.id)
        HStack(spacing: 12) {
            SignBadge(text: "\(chapter.position)", size: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.shortIT).font(.subheadline)
                Text(chapter.shortTitle(preferences.helperLanguage)).font(.footnote).foregroundStyle(.secondary)
                ThinProgressBar(value: Double(summary.correct) / Double(max(chapter.questionCount, 1)), height: 5)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(summary.correct)/\(chapter.questionCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if summary.mistakes > 0 {
                    Pill(Text("\(summary.mistakes) to clear"), tint: .falso)
                }
            }
        }
        .environment(\.alwaysShowsTranslations, true)
    }
}

/// Opened from Today's week chart: the streak, the week's totals and accuracy, and each day.
struct WeekDetailView: View {
    @Environment(ProgressStore.self) private var progress
    @State private var sharing = false

    var body: some View {
        let days = progress.activity
        let questions = days.reduce(0) { $0 + $1.questions }
        let correct = days.reduce(0) { $0 + $1.correctQuestions }
        let cards = days.reduce(0) { $0 + $1.cards }
        List {
            Section {
                HStack(alignment: .top) {
                    figure(Text(progress.streakDays(), format: .number), Text("Day streak"))
                    figure(Text(questions + cards, format: .number), Text("Answers"))
                    if questions > 0 {
                        figure(Text(Double(correct) / Double(questions), format: .percent.precision(.fractionLength(0))), Text("Accuracy"))
                    }
                }
                .padding(.vertical, 4)
                WeekChart(days: days).frame(height: 180)
                    .padding(.vertical, 8)
            }
            Section {
                ForEach(days.reversed()) { day in
                    HStack {
                        Text(day.day, format: .dateTime.weekday(.wide).day().month())
                            .foregroundStyle(day.questions + day.cards == 0 ? .secondary : .primary)
                        Spacer()
                        if day.questions + day.cards == 0 {
                            Text(verbatim: "—").foregroundStyle(.tertiary)
                        } else {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(day.questions) questions").font(.subheadline.monospacedDigit())
                                Text("\(day.cards) cards").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text(day.accuracy ?? 0, format: .percent.precision(.fractionLength(0)))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle((day.accuracy ?? 0) >= 0.9 ? Color.vero : .primary)
                                .frame(width: 52, alignment: .trailing)
                                .opacity(day.accuracy == nil ? 0 : 1)
                                .accessibilityHidden(day.accuracy == nil)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sharing = true } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $sharing) {
            CloseSheet(detents: [.large]) { StoryShareSheet(moments: StoryMoment.weekChoices(progress)) }
        }
    }

    private func figure(_ value: Text, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value.font(.title2.weight(.semibold)).monospacedDigit()
            label.font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Questions and cards answered per day, stacked.
struct WeekChart: View {
    let days: [DayActivity]

    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Questions", day.questions))
                .foregroundStyle(by: .value("Type", Preferences.shared.string("Questions")))
            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Cards", day.cards))
                .foregroundStyle(by: .value("Type", Preferences.shared.string("Cards")))
        }
        .chartForegroundStyleScale([Preferences.shared.string("Questions"): Color.vero, Preferences.shared.string("Cards"): Color.signBlue])
        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
    }
}
