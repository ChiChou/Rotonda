import Charts
import SwiftUI

struct TodayView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            WideLayout { wide in
                if wide {
                    dashboard
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        GreetingHeader()
                        nextSteps
                        LauncherGrid()
                        DueCard()
                        WeakSpotsCard(limit: 1)
                        StatTiles()
                        ExamWordsCard()
                        // Further down on iPhone, so the first screen stays about what to start.
                        DailyChallengeCard()
                        WeekCard()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(AppBrand.name)
        .toolbarTitleDisplayMode(.inline)
        .profileToolbar()
        // For the daily challenge's statements. Applied after the profile button so it sits to
        // its left, like the toggle on every other screen.
        .translationToggle()
    }

    /// A wide iPad window: two equal columns. Things to start on the left; the daily
    /// challenge, weak spots and progress on the right.
    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            GreetingHeader(large: true)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    nextSteps
                    LauncherGrid()
                    DueCard()
                    ExamWordsCard(chips: 6)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 16) {
                    DailyChallengeCard()
                    WeakSpotsCard()
                    StatTiles()
                    WeekCard(chartHeight: 140)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var nextSteps: some View {
        let chapter = nextChapter
        if let chapter { TodayStudyCard(chapter: chapter) }
        // Learn & quiz above already resumes that chapter; other activities in it skip the repeated name.
        if let last = progress.lastSession, last.isResumable, last != chapter.map({ .learnQuiz(chapter: $0.id) }) {
            ContinueCard(session: last, namesChapter: last.chapterID != chapter?.id)
        }
    }

    private var nextChapter: Chapter? {
        SessionBuilder.nextLearnQuizChapter()
    }
}

/// An Italian greeting for the time of day — a tiny daily dose of real Italian.
private struct GreetingHeader: View {
    var large = false

    var body: some View {
        let hour = Calendar.current.component(.hour, from: .now)
        // Italians keep saying "buonasera" until bed; "buonanotte" is only a goodbye.
        let italian = hour < 5 ? "Buonasera!" : hour < 13 ? "Buongiorno!" : hour < 18 ? "Buon pomeriggio!" : "Buonasera!"
        Text(verbatim: italian)
            // Above the card titles (headline) so the page has one clear heading.
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, large ? 8 : 4)
    }
}

/// The next chapter step. The whole card starts it.
private struct TodayStudyCard: View {
    let chapter: Chapter
    var fillsHeight = false
    @Environment(Preferences.self) private var preferences
    @Environment(SessionCoordinator.self) private var sessions

    var body: some View {
        let started = SessionBuilder.learnQuizDone(chapter) > 0
        Button { sessions.start(.learnQuiz(chapter: chapter.id)) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Learn & quiz").font(.subheadline.weight(.semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(chapter.shortIT)
                            .font(.headline)
                        Text(chapter.shortTitle(preferences.helperLanguage))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PlayBadge(tint: Color(light: 0x075DA8, dark: 0x075DA8), onTintedCard: true)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxHeight: fillsHeight ? .infinity : nil)
            .background(.signGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(CardButtonStyle(cornerRadius: 20))
        .accessibilityLabel(started ? Text("Continue") : Text("Start learning"))
        .accessibilityValue(Text(verbatim: chapter.shortIT))
    }
}

private struct ContinueCard: View {
    let session: StudySession
    var namesChapter = true
    var fillsHeight = false
    @Environment(SessionCoordinator.self) private var sessions
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @ScaledMetric(relativeTo: .title3) private var iconSize = 46.0

    var body: some View {
        Button { sessions.start(session) } label: {
            HStack(spacing: 14) {
                Image(systemName: session.icon)
                    .font(.title3.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.signBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Continue").font(.caption.weight(.bold)).foregroundStyle(Color.signBlue).textCase(.uppercase)
                    Group {
                        if namesChapter { SessionTitle(session: session) } else { session.activityTitle }
                    }
                    .font(.headline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    if case .read(let chapter) = session {
                        Text("Question \(progress.readingPosition("chapter-\(chapter)") + 1) of \(ContentStore.shared.chapter(chapter)?.questionCount ?? 0)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .cardStyle(padding: 14, fillsHeight: fillsHeight)
        }
        .buttonStyle(CardButtonStyle())
    }
}

private struct DueCard: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(SessionCoordinator.self) private var sessions

    var body: some View {
        let words = progress.dueCardIDs(prefix: "w:").count
        let facts = progress.dueCardIDs(prefix: "f:").count
        let questions = progress.dueQuestionIDs.count
        if words + facts + questions > 0 {
            Card {
                Text("Due for review").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(words + facts + questions) to review").font(.title2.weight(.bold))
                // The breakdown only when there is more than one kind.
                if [words, facts, questions].count(where: { $0 > 0 }) > 1 {
                    HStack(spacing: 8) {
                        if words > 0 { Pill(Text("\(words) words"), tint: .signBlue) }
                        if facts > 0 { Pill(Text("\(facts) facts"), tint: .amberInk) }
                        if questions > 0 { Pill(Text("\(questions) questions"), tint: .falso) }
                    }
                }
                Button("Review") { sessions.start(.review) }
                    .buttonStyle(FilledButtonStyle())
                    .padding(.top, 4)
            }
        }
    }
}

private struct WeekCard: View {
    var chartHeight: CGFloat = 120
    var fillsHeight = false
    @Environment(ProgressStore.self) private var progress
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            Card(fillsHeight: fillsHeight) {
                HStack {
                    Text("This week").font(.headline)
                    Spacer()
                    let total = progress.activity.reduce(0) { $0 + $1.questions + $1.cards }
                    Text("\(total) answers").font(.subheadline).foregroundStyle(.secondary)
                    DetailChevron()
                }
                WeekChart(days: progress.activity)
                    .frame(minHeight: chartHeight, maxHeight: fillsHeight ? .infinity : chartHeight)
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .sheet(isPresented: $showsDetails) { CloseSheet(detents: [.large]) { WeekDetailView() } }
    }
}

/// Marks a card that opens more detail.
private struct DetailChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(UIColor.tertiaryLabel))
            .accessibilityHidden(true)
    }
}
