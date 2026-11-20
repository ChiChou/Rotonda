import SwiftUI

/// Vocabulary measured by the exam: how much of the question bank the learner's words cover,
/// and the words that open the most questions next.
struct ExamWordsCard: View {
    var chips = 4
    var fillsHeight = false
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions

    var body: some View {
        let summary = WordReach.summary()
        let next = ContentStore.shared.words(ids: WordReach.nextWordIDs(limit: chips))
        let opened = WordReach.questionsOpened(by: WordReach.nextWordIDs(limit: Preferences.shared.sessionLength))
        Card(fillsHeight: fillsHeight) {
            Text("Exam vocabulary").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.wordShare, format: .percent.precision(.fractionLength(0)))
                        .font(.title2.weight(.semibold)).foregroundStyle(Color.signBlue)
                    Text("of the words in exam questions").font(.caption).foregroundStyle(.secondary)
                }
                ThinProgressBar(value: summary.wordShare)
                Text("\(summary.readable) of \(summary.total) questions fully readable")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Next words").font(.subheadline.weight(.semibold))
                        Spacer()
                        if opened > 0 {
                            Text("Opens \(opened) more questions").font(.caption).foregroundStyle(Color.vero)
                        }
                    }
                    FlowLayout {
                        ForEach(Array(next.enumerated()), id: \.element.id) { index, word in
                            NavigationLink { WordPagerView(title: Text("Next words"), words: next, start: index) } label: {
                                WordChip(word: word).foregroundStyle(Color.primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6).padding(.bottom, 6)
                        }
                    }
                }
            }
            if fillsHeight { Spacer(minLength: 0) }
            Button("Learn") { sessions.start(.words(.reach)) }
                .buttonStyle(FilledButtonStyle())
                .padding(.top, 4)
        }
    }
}
