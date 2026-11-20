import SwiftUI

/// Five statements a day, answered right on Today. The same set all day; answers count
/// like any other practice answer. The questions scroll sideways like a Home Screen widget
/// stack, answered or not, clipped by the card so it never leaves its place on Today.
struct DailyChallenge: Codable, Equatable {
    static let count = 5
    static let stateKey = "progress.dailyChallenge"

    var day: Int
    var ids: [Int]
    /// The answer given to each question, by question id.
    var answers: [Int: Bool] = [:]
    /// The question on screen.
    var position = 0

    var isFinished: Bool { position >= ids.count }

    static var currentDay: Int { Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0 }

    /// Today's challenge, resumed if it was started.
    static func today() -> DailyChallenge {
        let day = currentDay
        if let saved = ProgressStore.shared.state(DailyChallenge.self, for: ProgressStore.licenceKey(stateKey)), saved.day == day {
            return saved
        }
        return DailyChallenge(day: day, ids: pick(day: day))
    }

    func save() {
        ProgressStore.shared.setState(self, for: ProgressStore.licenceKey(Self.stateKey))
    }

    /// Up to two open mistakes, then statements from the chapters already started (or the next
    /// one), preferring ones with a picture.
    private static func pick(day: Int) -> [Int] {
        var random = SeededGenerator(seed: UInt64(day))
        let progress = ProgressStore.shared
        let content = ContentStore.shared
        var ids = Array(progress.mistakeIDs.shuffled(using: &random).prefix(2))
        let next = SessionBuilder.nextLearnQuizChapter()?.id
        var chapters = content.chapters.filter { progress.summary(chapter: $0.id).answered > 0 || $0.id == next }.map(\.id)
        if chapters.isEmpty { chapters = content.chapters.prefix(1).map(\.id) }
        let pool = chapters.flatMap { content.questions(chapter: $0) }.filter { !ids.contains($0.id) }.shuffled(using: &random)
        let pictured = pool.filter { $0.image != nil }
        let plain = pool.filter { $0.image == nil }
        let wanted = count - ids.count
        let withPicture = min(pictured.count, wanted - wanted / 3)
        ids += pictured.prefix(withPicture).map(\.id)
        ids += plain.prefix(count - ids.count).map(\.id)
        if ids.count < count { ids += pictured.dropFirst(withPicture).prefix(count - ids.count).map(\.id) }
        return ids.shuffled(using: &random)
    }
}

/// A repeatable random sequence, so the day's set is the same every time it is drawn.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct DailyChallengeCard: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(Preferences.self) private var preferences
    @Environment(SessionCoordinator.self) private var sessions
    @State private var challenge: DailyChallenge?
    @State private var questions: [Question] = []
    @State private var timer = AnswerTimer()
    /// The page in view: a question, or the result after the last one.
    @State private var visible: Int?
    /// Each page's natural height, so the card fits the page in view rather than the tallest.
    @State private var heights: [Int: CGFloat] = [:]

    var body: some View {
        Group {
            if let challenge, !questions.isEmpty {
                card(challenge)
            } else {
                Card { ProgressView().frame(maxWidth: .infinity, minHeight: 200) }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard challenge?.day != DailyChallenge.currentDay else { return }
        let today = DailyChallenge.today()
        questions = ContentStore.shared.questions(ids: today.ids)
        challenge = today
        visible = min(today.position, today.ids.count - 1 + (today.answers.count == today.ids.count ? 1 : 0))
    }

    private func card(_ challenge: DailyChallenge) -> some View {
        let count = challenge.ids.count
        // The result page joins once every question is answered.
        let pages = Array(0..<(count + (challenge.answers.count == count ? 1 : 0)))
        let correct = questions.count { challenge.answers[$0.id] == $0.answer }
        return Card {
            HStack {
                Text("Daily challenge").font(.headline)
                Spacer()
                dots(challenge)
            }
            // Pages scroll continuously, answered or not, like a Home Screen widget stack. The
            // scroll view reaches the card's edges, so the card clips them and stays in place.
            ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(pages, id: \.self) { index in
                        // Measured at the page's real width, so the card can fit the page in view.
                        page(index, challenge)
                            .padding(.horizontal, 16)
                            .containerRelativeFrame(.horizontal)
                            .fixedSize(horizontal: false, vertical: true)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[index] = $0 }
                            .frame(maxHeight: .infinity, alignment: .top)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $visible)
            .frame(height: heights[visible ?? 0], alignment: .top)
            .animation(.snappy, value: visible)
            .padding(.horizontal, -16)
            // The scroll position binding does not move a scroll view that is not laid out yet.
            .onAppear { proxy.scrollTo(visible ?? 0, anchor: .leading) }
            }
            .onChange(of: visible) { _, page in
                guard let page, var updated = self.challenge, updated.position != page else { return }
                updated.position = page
                updated.save()
                self.challenge = updated
                timer = AnswerTimer()
            }
        }
        .answerTimer($timer)
        .sensoryFeedback(.success, trigger: correct)
        .sensoryFeedback(.error, trigger: challenge.answers.count - correct)
    }

    @ViewBuilder private func page(_ index: Int, _ challenge: DailyChallenge) -> some View {
        if index < challenge.ids.count, let question = questions.first(where: { $0.id == challenge.ids[index] }) {
            VStack(alignment: .leading, spacing: 12) {
                // A preview, not a session: the same modest sizes on every screen.
                QuestionCard(question: question, imageHeight: 110, framed: false,
                             textFont: .headline, imageFillsWidth: false)
                if let chosen = challenge.answers[question.id] {
                    feedback(question, chosen: chosen)
                } else {
                    HStack(spacing: 12) {
                        answerButton(question, value: false)
                        answerButton(question, value: true)
                    }
                }
            }
        } else {
            finished(challenge)
        }
    }

    private func dots(_ challenge: DailyChallenge) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(challenge.ids.enumerated()), id: \.offset) { index, id in
                let answer = challenge.answers[id]
                let correct = answer.map { $0 == questions.first { $0.id == id }?.answer }
                Capsule()
                    .fill(correct == true ? Color.vero : correct == false ? Color.falso
                          : index == challenge.position ? Color.signBlue : Color.secondary.opacity(0.25))
                    .frame(width: index == challenge.position && !challenge.isFinished ? 22 : 10, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(min(challenge.position + 1, challenge.ids.count)) of \(challenge.ids.count)"))
    }

    private func answerButton(_ question: Question, value: Bool) -> some View {
        let tint = value ? Color(light: 0x16733E, dark: 0x16733E) : Color(light: 0xB82B23, dark: 0xB82B23)
        return Button { answer(question, value) } label: {
            Text(verbatim: value ? "VERO" : "FALSO").font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardButtonStyle(cornerRadius: 12))
    }

    private func feedback(_ question: Question, chosen: Bool) -> some View {
        let correct = chosen == question.answer
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill").font(.title2)
                Text(correct ? "Correct" : "Incorrect").font(.headline)
                Spacer()
                if !correct { VerdictLabel(answer: question.answer, compact: true) }
            }
            .foregroundStyle(correct ? Color.vero : Color.falso)
            let explanation = question.explanation(preferences.helperLanguage).ifEmpty(question.italianExplanation)
            if !explanation.isEmpty {
                Text(explanation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background((correct ? Color.vero : Color.falso).opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func finished(_ challenge: DailyChallenge) -> some View {
        let correct = questions.count { challenge.answers[$0.id] == $0.answer }
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(correct) of \(challenge.ids.count) correct").font(.title2.weight(.bold))
            Text("New questions tomorrow").font(.subheadline).foregroundStyle(.secondary)
            Button("Quick quiz") { sessions.start(.practice(.quickMix)) }
                .buttonStyle(FilledButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answer(_ question: Question, _ value: Bool) {
        guard var challenge, challenge.answers[question.id] == nil else { return }
        progress.record(question, answer: value,
                        hesitant: StudySchedule.isHesitant(seconds: timer.seconds, characters: question.textIT.count))
        challenge.answers[question.id] = value
        challenge.save()
        withAnimation(.snappy) { self.challenge = challenge }
    }
}
