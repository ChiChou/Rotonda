import SwiftUI
import WidgetKit

/// What is due right now, and when the next reviews arrive. Counts grow on schedule
/// without the app running, because the snapshot carries upcoming due times.
struct ReviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.Kind.review, provider: ReviewProvider()) { entry in
            ReviewWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Review")
        .description("Words, facts and questions due for review.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ReviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: .now, snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetShared.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetShared.loadSnapshot()
        let horizon = now.addingTimeInterval(86_400)
        // One entry per minute in which something falls due.
        var dates = [now]
        for item in snapshot?.upcoming ?? [] where item.due > now && item.due <= horizon {
            let minute = Date(timeIntervalSinceReferenceDate: (item.due.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
            if minute != dates.last { dates.append(minute) }
            if dates.count >= 60 { break }
        }
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(dates.count > 1 ? dates.last! : horizon)))
    }
}

struct ReviewWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            content(snapshot)
                .widgetURL(snapshot.dueCounts(at: entry.date).total > 0 ? WidgetLink.review.url : nil)
        } else if family == .systemSmall || family == .systemMedium {
            OpenAppPrompt()
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
    }

    @ViewBuilder
    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let counts = snapshot.dueCounts(at: entry.date)
        let next = snapshot.nextDue(after: entry.date)
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.caption2.weight(.bold))
                    Text("\(counts.total)").font(.title3.weight(.bold)).monospacedDigit().minimumScaleFactor(0.5)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Review", systemImage: "arrow.triangle.2.circlepath").font(.headline).widgetAccentable()
                if counts.total > 0 {
                    Text("\(counts.total) due").font(.body.weight(.semibold))
                    BreakdownLine(counts: counts).font(.caption)
                } else {
                    Text("All caught up")
                    if let next { Text("Next at \(reviewTime(next))").font(.caption) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            if counts.total > 0 {
                Label("\(counts.total) to review", systemImage: "arrow.triangle.2.circlepath")
            } else if let next {
                Label("Next review at \(reviewTime(next))", systemImage: "checkmark")
            } else {
                Label("All caught up", systemImage: "checkmark")
            }
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeader(title: "Review", icon: "arrow.triangle.2.circlepath")
                    Spacer(minLength: 0)
                    BigCount(counts: counts)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    KindRows(counts: counts)
                    Spacer(minLength: 0)
                    LaterToday(snapshot: snapshot, date: entry.date, counts: counts, next: next)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Review", icon: "arrow.triangle.2.circlepath")
                Spacer(minLength: 0)
                BigCount(counts: counts)
                if counts.total > 0 {
                    BreakdownLine(counts: counts).font(.caption).foregroundStyle(.secondary)
                } else if let next {
                    Text("Next at \(reviewTime(next))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct BigCount: View {
    let counts: WidgetSnapshot.ReviewCounts

    var body: some View {
        if counts.total > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(counts.total)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text("due now").font(.subheadline.weight(.semibold))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Color.vero).widgetAccentable()
                Text("All caught up").font(.subheadline.weight(.semibold))
            }
        }
    }
}

/// "8 words, 3 facts" — only the kinds that have something due.
private struct BreakdownLine: View {
    let counts: WidgetSnapshot.ReviewCounts

    var body: some View {
        let parts = [counts.words > 0 ? String(localized: "\(counts.words) words") : nil,
                     counts.facts > 0 ? String(localized: "\(counts.facts) facts") : nil,
                     counts.questions > 0 ? String(localized: "\(counts.questions) questions") : nil].compactMap { $0 }
        Text(parts.formatted(.list(type: .and, width: .narrow))).lineLimit(2)
    }
}

private struct KindRows: View {
    let counts: WidgetSnapshot.ReviewCounts

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Words", counts.words, "character.book.closed.fill", .signBlue)
            row("Facts", counts.facts, "number.square.fill", .amber)
            row("Questions", counts.questions, "checkmark.circle.fill", .falso)
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Int, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint).widgetAccentable()
            Text(title).foregroundStyle(value > 0 ? .primary : .secondary)
            Spacer(minLength: 4)
            Text("\(value)").monospacedDigit().fontWeight(.semibold).foregroundStyle(value > 0 ? .primary : .secondary)
        }
        .font(.subheadline)
    }
}

/// How much more arrives before midnight, so the learner can plan another session.
private struct LaterToday: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let counts: WidgetSnapshot.ReviewCounts
    let next: Date?

    var body: some View {
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        let later = snapshot.dueCounts(at: endOfDay).total - counts.total
        if let next, next < endOfDay, later > 0 {
            Text("+\(later) by tonight, next at \(reviewTime(next))")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        } else if let next {
            Text("Next at \(reviewTime(next))").font(.caption).foregroundStyle(.secondary)
        }
    }
}
