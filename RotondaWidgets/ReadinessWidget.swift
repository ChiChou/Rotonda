import SwiftUI
import WidgetKit

/// How close the learner is to passing: bank mastery, the chance of passing a mock exam
/// at the recent accuracy, the latest mock exams and the chapter that needs work.
struct ReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.readiness, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName("Exam readiness")
        .description("Readiness, mock exams and the chapter to focus on.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetShared.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The streak changes at midnight; everything else changes only when the app publishes.
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: WidgetShared.loadSnapshot())], policy: .after(midnight)))
    }
}

struct ReadinessWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else if family == .systemSmall || family == .systemMedium {
                OpenAppPrompt()
            } else {
                Image(systemName: "graduationcap.fill")
            }
        }
        .containerBackground(for: .widget) {
            if renderingMode == .fullColor { Rectangle().fill(.signGradient) } else { Color.clear }
        }
    }

    private var onBrand: Bool { renderingMode == .fullColor && (family == .systemSmall || family == .systemMedium) }

    /// A streak only counts while today or yesterday had study.
    private func streak(_ snapshot: WidgetSnapshot) -> Int {
        let calendar = Calendar.current
        if calendar.isDate(snapshot.generated, inSameDayAs: entry.date) { return snapshot.streak }
        if snapshot.studiedToday, let yesterday = calendar.date(byAdding: .day, value: -1, to: entry.date),
           calendar.isDate(snapshot.generated, inSameDayAs: yesterday) { return snapshot.streak }
        return 0
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snapshot.mastery) {
                Image(systemName: "graduationcap.fill")
            } currentValueLabel: {
                Text(snapshot.mastery.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetURL(WidgetLink.exam.url)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let chance = snapshot.passChance {
                    Text("Readiness \(chance.formatted(.percent.precision(.fractionLength(0))))").font(.headline).widgetAccentable()
                } else {
                    Text("\(snapshot.mastery.formatted(.percent.precision(.fractionLength(0)))) mastered").font(.headline).widgetAccentable()
                }
                if snapshot.exams.isEmpty {
                    Text("No mock exam yet").font(.caption)
                } else {
                    ExamPips(exams: snapshot.exams, height: 14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(WidgetLink.exam.url)
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    summary(snapshot)
                    Spacer(minLength: 0)
                    exams(snapshot)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let focus = snapshot.focus {
                    Link(destination: link(focus).url) { FocusPanel(focus: focus, onBrand: onBrand) }
                        .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(onBrand ? .white : .primary)
            .widgetURL(WidgetLink.exam.url)
        default:
            VStack(alignment: .leading, spacing: 6) {
                summary(snapshot)
                Spacer(minLength: 0)
                exams(snapshot)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(onBrand ? .white : .primary)
            .widgetURL(WidgetLink.exam.url)
        }
    }

    private func summary(_ snapshot: WidgetSnapshot) -> some View {
        let mastery = snapshot.mastery.formatted(.percent.precision(.fractionLength(0)))
        let chance = snapshot.passChance
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MasteryRing(value: snapshot.mastery, lineWidth: 4, tint: onBrand ? .white : .signBlue, showsValue: false)
                    .frame(width: 20, height: 20)
                Group {
                    if chance != nil {
                        Text("\(mastery) mastered")
                    } else {
                        Text("\(snapshot.mastered) of \(snapshot.questionCount)")
                    }
                }
                .font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                let days = streak(snapshot)
                if days > 0 {
                    Label("\(days)", systemImage: "flame.fill")
                        .labelStyle(CompactLabel())
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(onBrand ? Color.white : Color.amberInk)
                        .accessibilityLabel(Text("\(days)-day streak"))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(chance == nil ? "Mastered" : "Readiness").font(.caption.weight(.semibold)).opacity(0.85)
                Text((chance ?? snapshot.mastery).formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
    }

    @ViewBuilder
    private func exams(_ snapshot: WidgetSnapshot) -> some View {
        if snapshot.exams.isEmpty {
            Text("No mock exam yet").font(.caption.weight(.semibold)).opacity(0.85)
        } else {
            ExamPips(exams: snapshot.exams, onTint: onBrand)
        }
    }

    private func link(_ focus: WidgetSnapshot.Focus) -> WidgetLink {
        focus.reason == .mistakes ? .chapterMistakes(chapter: focus.chapterID) : .learn(chapter: focus.chapterID)
    }
}

private struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon; configuration.title }
    }
}

/// The chapter to work on next, with the reason it was picked.
private struct FocusPanel: View {
    let focus: WidgetSnapshot.Focus
    let onBrand: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(focus.reason == .mistakes ? "Focus" : "Up next")
                .font(.caption.weight(.bold)).textCase(.uppercase).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(focus.position)").font(.system(.subheadline, design: .rounded).weight(.heavy)).monospacedDigit()
                VStack(alignment: .leading, spacing: 3) {
                    Text(focus.titleIT).font(.subheadline.weight(.semibold)).lineLimit(3).minimumScaleFactor(0.8)
                    Text(focus.titleHelper).font(.caption).lineLimit(2).opacity(0.85)
                }
            }
            Spacer(minLength: 0)
            if focus.reason == .mistakes {
                Label("\(focus.mistakes) mistakes", systemImage: "xmark.circle.fill").font(.caption.weight(.semibold))
            } else {
                Text("\(focus.answered) of \(focus.total)").font(.caption.weight(.semibold)).monospacedDigit()
                Capsule().fill(.white.opacity(onBrand ? 0.3 : 0))
                    .background(Capsule().fill(Color.signBlue.opacity(onBrand ? 0 : 0.2)))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule().fill(onBrand ? Color.white : Color.signBlue)
                                .frame(width: geometry.size.width * Double(focus.answered) / Double(max(focus.total, 1)))
                        }
                    }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(onBrand ? Color.white.opacity(0.16) : Color.signBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
