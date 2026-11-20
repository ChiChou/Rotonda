import SwiftUI

/// Browse a chapter horizontally with answers visible. The position is saved on every
/// page, so it resumes after any interruption; vertical scrolling reads longer content.
struct ReaderSessionView: View {
    let chapterID: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @State private var questions: [Question] = []
    @State private var current: Int?
    @State private var showsJumpList = false

    private var key: String { "chapter-\(chapterID)" }

    var body: some View {
        VStack(spacing: 0) {
            SessionTopBar(title: SessionTitle(session: .read(chapter: chapterID)),
                          position: (current ?? 0) + 1, total: questions.count,
                          openJumpList: { showsJumpList = true }) {
                SpeechController.shared.stop()
                dismiss()
            }
            StudyPager(items: questions, position: $current) { QuestionPage(question: $0) }
        }
        .screenBackground()
        .sheet(isPresented: $showsJumpList) {
            CloseSheet(detents: [.large]) {
                PageJumpList(items: questions, current: current ?? 0, searchText: { $0.textIT },
                             select: { current = $0 }) { QuestionJumpRow(question: $0) }
            }
        }
        .swipeToClose {
            SpeechController.shared.stop()
            dismiss()
        }
        .onAppear {
            questions = ContentStore.shared.questions(chapter: chapterID)
            let saved = progress.readingPosition(key)
            current = saved < questions.count ? saved : 0
        }
        .onChange(of: current) { _, value in
            if let value { progress.setReadingPosition(value, for: key) }
        }
    }
}
