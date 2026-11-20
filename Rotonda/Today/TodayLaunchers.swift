import SwiftUI

/// The main ways to practise as blocks with an icon, a name and a live count, two per row:
/// short rows on iPhone, larger blocks that fill the column on iPad.
struct LauncherGrid: View {
    @Environment(SessionCoordinator.self) private var sessions
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .body) private var compactIconSize = 34.0
    @ScaledMetric(relativeTo: .title3) private var regularIconSize = 44.0

    private struct Item: Identifiable {
        let title: LocalizedStringKey
        let icon: String
        let detail: Text
        /// A shorter detail for when the full one does not fit on one line.
        var shortDetail: Text? = nil
        let session: StudySession
        var id: StudySession { session }
    }

    private var items: [Item] {
        allItems.compactMap { $0 }
    }

    private var allItems: [Item?] {
        let length = preferences.sessionLength
        let mistakes = progress.mistakeIDs.count
        let rules = ContentStore.shared.examRules
        return [
            Item(title: "Quick quiz", icon: "checkmark", detail: Text("\(length) questions"), session: .practice(.quickMix)),
            Item(title: "Mock exam", icon: "stopwatch", detail: Text("\(rules.questionCount) questions, \(rules.minutes) min"),
                 shortDetail: Text("\(rules.minutes) min"), session: .exam),
            ContentStore.shared.hasPictures
                ? Item(title: "Signs", icon: "exclamationmark.triangle.fill", detail: Text("\(length) questions"), session: .practice(.signs))
                : nil,
            Item(title: "Mistakes", icon: "arrow.uturn.backward", detail: Text("\(mistakes) to clear"),
                 session: .practice(.mistakes)),
            Item(title: "Words", icon: "character.book.closed.fill", detail: Text("\(length) cards"), session: .words(.ladder)),
            Item(title: "Listen", icon: "headphones", detail: Text("\(length) questions"), session: .listen(.quickMix)),
        ]
    }

    var body: some View {
        let compact = sizeClass == .compact
        let columns = dynamicTypeSize >= .xxxLarge ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: compact ? 10 : 12), count: columns),
                  spacing: compact ? 10 : 12) {
            ForEach(items) { item in
                Button { sessions.start(item.session) } label: {
                    block(item, compact: compact)
                        // Equal heights across a row when a label wraps.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous))
                }
                .buttonStyle(CardButtonStyle())
            }
        }
    }

    /// iPhone: a small icon beside the name, in a short row. iPad: a larger icon above the
    /// text, so the blocks fill the column.
    @ViewBuilder private func block(_ item: Item, compact: Bool) -> some View {
        if compact {
            HStack(spacing: 10) {
                icon(item, size: compactIconSize, font: .body.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                        .lineLimit(2)
                    detail(item).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                icon(item, size: regularIconSize, font: .title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline).foregroundStyle(Color.primary)
                        .lineLimit(2)
                    detail(item).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    /// The detail at full text size: the short form when the full one would not fit, rather
    /// than shrinking the text below its siblings'.
    @ViewBuilder private func detail(_ item: Item) -> some View {
        if let short = item.shortDetail {
            ViewThatFits(in: .horizontal) {
                item.detail.lineLimit(1)
                short.lineLimit(1)
            }
        } else {
            item.detail.lineLimit(2)
        }
    }

    private func icon(_ item: Item, size: CGFloat, font: Font) -> some View {
        Image(systemName: item.icon)
            .font(font)
            .foregroundStyle(Color.signBlue)
            .frame(width: size, height: size)
            .background(Color.signBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Three headline numbers side by side. Opens the progress details.
struct StatTiles: View {
    @Environment(ProgressStore.self) private var progress
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            HStack(alignment: .top, spacing: 12) {
                tile(Text(progress.streakDays(), format: .number), label: "day streak", tint: .amberInk)
                tile(Text(progress.bankMastery, format: .percent.precision(.fractionLength(0))), label: "mastered", tint: .signBlue)
                tile(Text(progress.learnedCount(prefix: "w:"), format: .number), label: "words learned", tint: .vero)
            }
        }
        // Tiles share the height of the tallest when a label wraps.
        .fixedSize(horizontal: false, vertical: true)
        .buttonStyle(CardButtonStyle())
        .sheet(isPresented: $showsDetails) { CloseSheet(detents: [.large]) { ProgressDetailView() } }
    }

    private func tile(_ value: Text, label: LocalizedStringKey, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            value.font(.title.weight(.bold)).monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Narrower sides than other cards: three tiles share a phone's width.
        .padding(.horizontal, 12).padding(.vertical, 16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
