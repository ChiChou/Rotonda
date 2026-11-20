import SwiftUI

/// Mock exam first, then chapter quizzes and quick practice.
struct QuizHomeView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MockExamCard()
                SplitLink(id: "chapters") { LearnQuizChaptersView() } label: {
                    FeatureRow(icon: "list.number", tint: .indigo, title: "Choose a chapter")
                        .cardStyle(padding: 14)
                }
                .buttonStyle(CardButtonStyle())

                SectionTitle(title: "Quick quizzes")
                Card(padding: 12) {
                    quizRow(.practice(.quickMix), icon: "shuffle", tint: .vero, title: "Mixed quiz")
                    Divider()
                    quizRow(.practice(.mistakes), icon: "exclamationmark.circle.fill", tint: .falso, title: "Mistakes",
                            subtitle: Text("\(progress.mistakeIDs.count) to clear"))
                        .disabled(progress.mistakeIDs.isEmpty)
                    Divider()
                    if ContentStore.shared.hasPictures {
                        quizRow(.practice(.signs), icon: "photo.on.rectangle.angled", tint: .falso, title: "Signs & pictures")
                        Divider()
                    }
                    quizRow(.wordQuiz(.ladder), icon: "character.textbox", tint: .signBlue, title: "Word quiz")
                    Divider()
                    quizRow(.numberQuiz(.due), icon: "number.circle.fill", tint: .amberInk, title: "Numbers quiz")
                    if !progress.bookmarks.isEmpty {
                        Divider()
                        quizRow(.practice(.bookmarks), icon: "bookmark.fill", tint: .signBlue, title: "Saved questions",
                                subtitle: Text(progress.bookmarks.count, format: .number))
                    }
                }

                if !progress.exams.isEmpty {
                    SectionTitle(title: "History", detail: Text("\(progress.exams.filter(\.passed).count) of \(progress.exams.count) passed"))
                    // The latest few; the full history has its own filtered list.
                    ForEach(progress.exams.prefix(Self.recentExams)) { exam in
                        Button { sessions.start(.examReview(examID: exam.id)) } label: { ExamRecordRow(exam: exam) }
                            .buttonStyle(CardButtonStyle())
                    }
                    if progress.exams.count > Self.recentExams {
                        SplitLink(id: "exams") { ExamHistoryView() } label: {
                            FeatureRow(icon: "clock.arrow.circlepath", tint: .signBlue, title: "All exams",
                                       subtitle: Text(progress.exams.count, format: .number))
                                .cardStyle(padding: 14)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Quiz")
        .toolbarTitleDisplayMode(.inline)
        .profileToolbar()
    }

    static let recentExams = 5

    private func quizRow(_ session: StudySession, icon: String, tint: Color, title: LocalizedStringKey, subtitle: Text? = nil) -> some View {
        Button { sessions.start(session) } label: {
            FeatureRow(icon: icon, tint: tint, title: title, subtitle: subtitle) {
                Image(systemName: "play.fill").foregroundStyle(tint)
            }
        }
        .buttonStyle(RowButtonStyle())
    }
}

struct LearnQuizChaptersView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions
    @State private var query = ""

    var body: some View {
        let chapters = ContentStore.shared.chapters.filter { $0.matches(query, language: preferences.helperLanguage) }
        List {
            if chapters.isEmpty { ContentUnavailableView.search(text: query) }
            Section {
                ForEach(chapters) { chapter in
                    let done = SessionBuilder.learnQuizDone(chapter)
                    Button { sessions.start(.learnQuiz(chapter: chapter.id)) } label: {
                        HStack(spacing: 12) {
                            SignBadge(text: "\(chapter.position)", size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.shortIT).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                                Text(chapter.shortTitle(preferences.helperLanguage)).font(.footnote).foregroundStyle(.secondary)
                                ThinProgressBar(value: Double(done) / Double(max(chapter.questionCount, 1)), tint: .indigo, height: 5)
                            }
                            Text("\(done)/\(chapter.questionCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .readableListMargins()
        .studySearch(text: $query)
        .navigationTitle("Learn & quiz")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every mock exam, newest first, filtered by result.
struct ExamHistoryView: View {
    enum Filter: Hashable { case all, passed, failed }

    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions
    @State private var filter = Filter.all

    var body: some View {
        let exams = progress.exams.filter {
            switch filter {
            case .all: true
            case .passed: $0.passed
            case .failed: !$0.passed
            }
        }
        List {
            Picker("Result", selection: $filter) {
                Text("All").tag(Filter.all)
                Text("Passed").tag(Filter.passed)
                Text("Not passed").tag(Filter.failed)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            Section {
                ForEach(exams) { exam in
                    Button { sessions.start(.examReview(examID: exam.id)) } label: { ExamRecordRow(exam: exam, inList: true) }
                        .buttonStyle(.plain)
                }
            }
        }
        .readableListMargins()
        .navigationTitle("All exams")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A small preview of the official exam screen, so the simulation is no surprise. The whole
/// card starts it.
struct MockExamCard: View {
    @Environment(SessionCoordinator.self) private var sessions

    var body: some View {
        Button { sessions.start(.exam) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Mock exam").font(.headline)
                    let rules = ContentStore.shared.examRules
                    HStack(alignment: .top, spacing: 12) {
                        rule("\(rules.questionCount)", Text("statements"))
                        rule("\(rules.minutes)′", Text("minutes"))
                        rule("≤\(rules.maxErrors)", Text("errors to pass"))
                    }
                }
                PlayBadge(tint: Color(light: 0x075DA8, dark: 0x075DA8), onTintedCard: true)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.signGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel(Text("Start simulation"))
    }

    private func rule(_ value: String, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.headline).monospacedDigit()
            label.font(.caption).opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExamRecordRow: View {
    let exam: ExamRecord
    /// In a List the row supplies its own background.
    var inList = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: exam.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.title2).foregroundStyle(exam.passed ? Color.vero : Color.falso)
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.passed ? "Passed" : "Not passed").font(.headline)
                Text(exam.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(exam.errors) errors").font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(Duration.seconds(exam.durationSeconds), format: .time(pattern: .minuteSecond)).font(.caption).foregroundStyle(.secondary)
            }
            if !exam.answers.isEmpty {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(inList ? 0 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inList ? Color.clear : Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
    }
}
