import SwiftUI

/// The chapters with the most open mistakes, each starting a quiz on them, and the unknown
/// words in those mistakes. Hidden until there are mistakes.
struct WeakSpotsCard: View {
    var limit = 3
    var fillsHeight = false
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions
    @ScaledMetric(relativeTo: .subheadline) private var iconSize = 30.0

    var body: some View {
        let ranked = ContentStore.shared.chapters
            .map { (chapter: $0, mistakes: progress.summary(chapter: $0.id).mistakes) }
            .filter { $0.mistakes > 0 }
            .sorted { $0.mistakes > $1.mistakes }
            .prefix(limit)
        let words = WordReach.mistakeWordIDs().count
        if !ranked.isEmpty {
            Card(padding: 12, fillsHeight: fillsHeight) {
                Text("Weak spots").font(.headline).padding(.horizontal, 4)
                ForEach(Array(ranked.enumerated()), id: \.element.chapter.id) { index, item in
                    if index > 0 { Divider() }
                    Button { sessions.start(.practice(.chapterMistakes(item.chapter.id))) } label: {
                        HStack(spacing: 12) {
                            SignBadge(text: "\(item.chapter.position)", size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.chapter.shortIT).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(2)
                                Text("\(item.mistakes) to clear").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "play.fill").foregroundStyle(Color.falso)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                    .accessibilityLabel(Text("Fix mistakes"))
                    .accessibilityValue(Text(verbatim: item.chapter.shortIT))
                }
                if words > 0 {
                    Divider()
                    Button { sessions.start(.words(.mistakes)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "character.book.closed.fill")
                                .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                                .frame(width: iconSize, height: iconSize)
                                .background(Color.signBlue, in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Words from mistakes").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                Text("\(words) words").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "play.fill").foregroundStyle(Color.signBlue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle())
                }
                if fillsHeight { Spacer(minLength: 0) }
            }
        }
    }
}
