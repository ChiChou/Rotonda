import SwiftUI
import UIKit

// MARK: - Swipe

struct SwipeAction {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    /// Throws the card off-screen before acting, for actions that move on to the next card.
    var leavesCard = false
    let perform: () -> Void
}

enum SwipeSide { case left, right }

/// Time from a card appearing to its answer. Leaving the app while the card is open, for a
/// call or another app, discards the time: an interruption is not hesitation.
struct AnswerTimer {
    var start: Date? = .now
    var seconds: TimeInterval? { start.map { Date.now.timeIntervalSince($0) } }
}

private struct AnswerTiming: ViewModifier {
    @Binding var timer: AnswerTimer
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { timer.start = .now }
            .onChange(of: scenePhase) { _, phase in if phase != .active { timer.start = nil } }
    }
}

extension View {
    func answerTimer(_ timer: Binding<AnswerTimer>) -> some View { modifier(AnswerTiming(timer: timer)) }
}

/// Drag a card sideways to act, like sorting cards on a table: a stamp fades in while
/// dragging and the action fires past the threshold. Vertical drags still scroll.
struct SwipeActions: ViewModifier {
    var left: SwipeAction?
    var right: SwipeAction?
    /// Set from outside (a grade button) to throw the card off that side and run its action.
    var fling: SwipeSide?
    var threshold: CGFloat = 100

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var armed = false
    @State private var gone = false
    @State private var width: CGFloat = 400

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .rotationEffect(.degrees(Double(offset) / 40), anchor: .bottom)
            .overlay(alignment: .topLeading) { stamp(right, progress: offset / threshold) }
            .overlay(alignment: .topTrailing) { stamp(left, progress: -offset / threshold) }
            .opacity(gone ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .gesture(
                HorizontalCardPan(enabled: left != nil || right != nil) { translation in
                    guard !gone else { return }
                    let dx = translation.x
                    let action = dx > 0 ? right : left
                    offset = action == nil ? dx / 5 : dx
                    armed = action != nil && abs(dx) > threshold
                } onEnded: { translation, velocity in
                    guard !gone else { return }
                    let dx = max(abs(translation.x), abs(translation.x + velocity.x * 0.15) * 0.6)
                        * ((translation.x == 0 ? velocity.x : translation.x) >= 0 ? 1 : -1)
                    let side: SwipeSide? = dx > threshold ? .right : (dx < -threshold ? .left : nil)
                    let action = side == .right ? right : (side == .left ? left : nil)
                    armed = false
                    if let side, action?.leavesCard == true { leave(side); return }
                    withAnimation(.snappy) { offset = 0 }
                    action?.perform()
                } onCancelled: {
                    armed = false
                    withAnimation(.snappy) { offset = 0 }
                }
            )
            .onChange(of: fling) { _, side in if let side { leave(side) } }
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, isArmed in isArmed }
    }

    /// The card keeps going the way it was thrown, tilting and fading, then the action runs.
    private func leave(_ side: SwipeSide) {
        guard !gone, let action = side == .left ? left : right else { return }
        withAnimation(.easeIn(duration: 0.22)) {
            if !reduceMotion { offset = (side == .left ? -1 : 1) * width * 1.4 }
            gone = true
        } completion: {
            action.perform()
        }
    }

    @ViewBuilder private func stamp(_ action: SwipeAction?, progress: CGFloat) -> some View {
        if let action, progress > 0.15 {
            Label(action.title, systemImage: action.icon)
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(action.color, in: Capsule())
                .opacity(min(progress, 1))
                .padding(14)
                .allowsHitTesting(false)
        }
    }
}

/// Reject vertical pans before recognition so the surrounding ScrollView can scroll.
private struct HorizontalCardPan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint, CGPoint) -> Void
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.isEnabled = enabled
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            context.coordinator.lastVelocity = recognizer.velocity(in: recognizer.view)
            onChanged(recognizer.translation(in: recognizer.view))
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view)
            onEnded(recognizer.translation(in: recognizer.view),
                    velocity.x == 0 ? context.coordinator.lastVelocity : velocity)
        case .cancelled, .failed: onCancelled()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var lastVelocity = CGPoint.zero

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * 1.3 else { return false }
            // A sideways swipe owns the drag: stop any vertical scroll that started with it, so
            // the page never moves on both axes at once.
            var view = pan.view?.superview
            while let current = view {
                // Only vertical scrollers; a horizontal pager keeps its own drag.
                if let scroll = current as? UIScrollView, scroll.contentSize.width <= scroll.bounds.width + 1 {
                    scroll.panGestureRecognizer.isEnabled = false
                    scroll.panGestureRecognizer.isEnabled = true
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension View {
    func swipeActions(left: SwipeAction? = nil, right: SwipeAction? = nil, fling: SwipeSide? = nil) -> some View {
        modifier(SwipeActions(left: left, right: right, fling: fling))
    }
}

// MARK: - Learn step

/// Learn first: the statement with its answer, explanation and key words — nothing to answer.
/// The quiz on exactly these statements comes right after the batch.
struct StudyQuestionView: View {
    let question: Question
    var onBack: (() -> Void)? = nil
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuestionCard(question: question)
                VerdictLabel(answer: question.answer)
                QuestionInsights(question: question, expanded: true)
            }
            .padding(16)
        }
        .accessibilityActions {
            Button("Next", action: onNext)
            if let onBack { Button("Previous", action: onBack) }
        }
    }
}

// MARK: - VERO / FALSO

/// Answer VERO/FALSO with the buttons, then instant feedback with the explanation, key words
/// and linked facts. Swiping only moves on, so a quick second swipe never answers the next card.
struct PracticeQuestionView: View {
    let question: Question
    /// The answer already given, when the learner swipes back to re-read this question.
    var answered: Bool? = nil
    var onBack: (() -> Void)? = nil
    var onChosen: (Bool) -> Void = { _ in }
    let onFinished: (Bool) -> Void

    @Environment(ProgressStore.self) private var progress
    @State private var chosen: Bool?
    @State private var timer = AnswerTimer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                QuestionCard(question: question)
                if let chosen {
                    feedback(chosen)
                    QuestionInsights(question: question)
                } else {
                    HStack(spacing: 12) {
                        answerButton(false)
                        answerButton(true)
                    }
                }
            }
            .padding(16)
        }
        .accessibilityActions {
            if chosen != nil { Button("Next", action: finish) }
            if let onBack { Button("Previous", action: onBack) }
        }
        .onAppear { if chosen == nil { chosen = answered } }
        .answerTimer($timer)
        .sensoryFeedback(trigger: chosen) { old, value in
            guard old != nil || answered == nil, let value else { return nil }
            return value == question.answer ? .success : .error
        }
    }

    private func answer(_ value: Bool) {
        guard chosen == nil else { return }
        withAnimation(.snappy) { chosen = value }
        progress.record(question, answer: value,
                        hesitant: StudySchedule.isHesitant(seconds: timer.seconds, characters: question.textIT.count))
        onChosen(value)
    }

    private func finish() {
        guard let chosen else { return }
        onFinished(chosen == question.answer)
    }

    private func feedback(_ chosen: Bool) -> some View {
        let correct = chosen == question.answer
        return HStack(spacing: 12) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill").font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(correct ? "Correct" : "Incorrect").font(.title3.weight(.bold))
                if !correct {
                    VerdictLabel(answer: question.answer)
                }
            }
            Spacer()
            Button { progress.toggleBookmark(question.id) } label: {
                Image(systemName: progress.bookmarks.contains(question.id) ? "bookmark.fill" : "bookmark")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.signBlue)
            .accessibilityLabel(Text("Save question"))
            .accessibilityAddTraits(progress.bookmarks.contains(question.id) ? .isSelected : [])
        }
        .foregroundStyle(correct ? Color.vero : Color.falso)
        .padding(14)
        .background((correct ? Color.vero : Color.falso).opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func answerButton(_ value: Bool) -> some View {
        Button { answer(value) } label: {
            Text(verbatim: value ? "VERO" : "FALSO").font(.title3.weight(.heavy))
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .glassButtonStyle(prominent: true)
        .tint(value ? Color(light: 0x16733E, dark: 0x16733E) : Color(light: 0xB82B23, dark: 0xB82B23))
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

// MARK: - Multiple choice

/// Shared multiple-choice layout: a prompt, four big options, feedback, then Next.
private struct ChoiceQuizLayout<Prompt: View, After: View>: View {
    let options: [String]
    let correctIndex: Int
    /// Whether the choice was right, and whether it took long enough to count as unsure.
    let onAnswer: (_ correct: Bool, _ hesitant: Bool) -> Void
    let onNext: (Bool) -> Void
    var answered: Int? = nil
    var onBack: (() -> Void)? = nil
    var onChosen: (Int) -> Void = { _ in }
    @ViewBuilder var prompt: Prompt
    @ViewBuilder var after: After

    @State private var chosen: Int?
    @State private var timer = AnswerTimer()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    prompt
                    VStack(spacing: 10) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            Button { choose(index) } label: {
                                HStack {
                                    Text(option).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                                    Spacer()
                                    if chosen != nil && index == correctIndex {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vero)
                                    } else if chosen == index {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.falso)
                                    }
                                }
                                .foregroundStyle(Color.primary)
                                .padding(16)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .background(background(index), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(chosen != nil)
                        }
                    }
                    if chosen != nil { after }
                }
                .padding(16)
            }
        }
        .accessibilityActions {
            if chosen != nil { Button("Next", action: next) }
            if let onBack { Button("Previous", action: onBack) }
        }
        .onAppear { if chosen == nil { chosen = answered } }
        .answerTimer($timer)
        .sensoryFeedback(trigger: chosen) { old, value in
            guard old != nil || answered == nil, let value else { return nil }
            return value == correctIndex ? .success : .error
        }
    }

    private func background(_ index: Int) -> Color {
        guard let chosen else { return .card }
        if index == correctIndex { return Color.vero.opacity(0.18) }
        if index == chosen { return Color.falso.opacity(0.18) }
        return .card
    }

    private func choose(_ index: Int) {
        guard chosen == nil else { return }
        withAnimation(.snappy) { chosen = index }
        let reading = options.reduce(0) { $0 + $1.count } + 20
        onAnswer(index == correctIndex, StudySchedule.isHesitant(seconds: timer.seconds, characters: reading))
        onChosen(index)
    }

    private func next() {
        guard let chosen else { return }
        onNext(chosen == correctIndex)
    }
}

/// Italian word → pick its meaning. Feeds the same spaced-repetition card as the flashcards.
struct WordChoiceView: View {
    /// Scales with Dynamic Type, unlike a fixed point size.
    @ScaledMetric(relativeTo: .largeTitle) private var lemmaSize = 38.0
    let word: Word
    let options: [Word]
    var answered: Int? = nil
    var onBack: (() -> Void)? = nil
    var onChosen: (Int) -> Void = { _ in }
    let onFinished: (Bool) -> Void

    @Environment(ProgressStore.self) private var progress

    var body: some View {
        ChoiceQuizLayout(options: options.map(SessionBuilder.helperGloss),
                         correctIndex: options.firstIndex(of: word) ?? 0,
                         onAnswer: { progress.review(word.cardID, known: $0, hesitant: $1) },
                         onNext: onFinished, answered: answered, onBack: onBack, onChosen: onChosen) {
            VStack(spacing: 12) {
                Text(word.lemma).font(.system(size: lemmaSize, weight: .bold)).minimumScaleFactor(0.5)
                ItalianSpeechButton(text: word.lemma, key: "choice-\(word.id)")
            }
            .frame(maxWidth: .infinity)
            .cardStyle(padding: 20)
        } after: {
            if !word.exampleIT.isEmpty {
                WordExampleText(word: word).cardStyle(padding: 14)
            }
        }
    }
}

/// A rule from the facts decks → pick the right number.
struct FactChoiceView: View {
    let fact: Fact
    let options: [String]
    var answered: Int? = nil
    var onBack: (() -> Void)? = nil
    /// Off in a session drawn from one deck, whose name is already in the header.
    var showsDeck = true
    var onChosen: (Int) -> Void = { _ in }
    let onFinished: (Bool) -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        ChoiceQuizLayout(options: options, correctIndex: options.firstIndex(of: fact.value) ?? 0,
                         onAnswer: { progress.review(fact.cardID, known: $0, hesitant: $1) },
                         onNext: onFinished, answered: answered, onBack: onBack, onChosen: onChosen) {
            VStack(alignment: .leading, spacing: 10) {
                if showsDeck {
                    Label { Text(fact.deck.title) } icon: { Image(systemName: fact.deck.icon) }
                        .font(.caption.weight(.bold)).foregroundStyle(Color.amberInk)
                }
                HStack(alignment: .top) {
                    TranslationText(original: fact.italianHeadline, translated: fact.topic(preferences.helperLanguage))
                        .font(.title3.weight(.bold))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } after: {
            FactCard(fact: fact, showsDeck: showsDeck)
        }
    }
}

// MARK: - Flashcards

/// Italian word on the front; meaning, warning and real exam usage on the back.
/// Swipe right when you know it, left to see it again soon.
struct WordFlashcardView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var lemmaSize = 40.0
    let word: Word
    let onGraded: (Bool) -> Void

    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @State private var revealed = false
    @State private var fling: SwipeSide?
    @State private var sample: Question?

    init(word: Word, onGraded: @escaping (Bool) -> Void) {
        self.word = word
        self.onGraded = onGraded
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        HStack {
                            if progress.status(word.cardID) == .new { Pill(Text("New"), tint: .signBlue) }
                            if word.kind == .exam { Pill(Text("Exam language"), tint: .amberInk) }
                            Spacer()
                            Text("in \(word.questionCount) questions").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(word.lemma).font(.system(size: lemmaSize, weight: .bold)).multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5).padding(.vertical, 18)
                        ItalianSpeechButton(text: word.lemma, key: "card-\(word.id)")
                        if revealed {
                            Divider()
                            GlossText(word: word, font: .title2.weight(.semibold)).multilineTextAlignment(.center)
                            let note = word.note(preferences.helperLanguage)
                            if !note.isEmpty {
                                Label { Text(note) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.amber) }
                                    .font(.callout).translationVisibility()
                            }
                            if !word.exampleIT.isEmpty {
                                VStack(spacing: 4) {
                                    Text(word.exampleIT).font(.callout.italic())
                                    let translation = word.exampleTranslation(preferences.helperLanguage)
                                    if !translation.isEmpty { Text(translation).font(.footnote).foregroundStyle(.secondary).translationVisibility() }
                                }
                                .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .cardStyle(padding: 20)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { revealed = true } }
                    .gradeSwipes(cardID: word.cardID, revealed: revealed, fling: fling, onGraded: onGraded)

                    if revealed, let sample {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("From the exam").font(.caption.weight(.bold)).foregroundStyle(.secondary).textCase(.uppercase)
                            QuestionRow(question: sample)
                        }
                    }
                }
                .padding(16)
            }
            GradeBar(revealed: $revealed, fling: $fling)
        }
        .task(id: word.id) {
            sample = ContentStore.shared.questionIDs(word: word.id).randomElement().flatMap { ContentStore.shared.question($0) }
        }
    }
}

/// A key number or rule: the question on the front, the value and rule on the back.
struct FactFlashcardView: View {
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 44.0
    let fact: Fact
    var showsDeck = true
    let onGraded: (Bool) -> Void

    @Environment(Preferences.self) private var preferences
    @State private var revealed = false
    @State private var fling: SwipeSide?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsDeck {
                        Label { Text(fact.deck.title) } icon: { Image(systemName: fact.deck.icon) }
                            .font(.caption.weight(.bold)).foregroundStyle(Color.amberInk)
                    }
                    HStack(alignment: .top) {
                        TranslationText(original: fact.italianHeadline, translated: fact.topic(preferences.helperLanguage))
                            .font(.title2.weight(.bold))
                        Spacer()
                    }
                    if revealed, !fact.value.isEmpty {
                        Text(fact.value).font(.system(size: valueSize, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.amberInk).minimumScaleFactor(0.5)
                    }
                    // The signs the statement is about, on the front: they set the scene, not the answer.
                    FactPictures(fact: fact)
                    if revealed {
                        HelperTranslation(text: fact.text(preferences.helperLanguage))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(Color.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.amber.opacity(0.5)))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { revealed = true } }
                .gradeSwipes(cardID: fact.cardID, revealed: revealed, fling: fling, onGraded: onGraded)
                .padding(16)
            }
            GradeBar(revealed: $revealed, fling: $fling)
        }
    }
}

private extension View {
    /// Right = "Got it", left = "Again", recorded in spaced repetition. The card flies off the
    /// way it was graded, whether swiped or graded with the buttons. Only a revealed card can be
    /// graded, like the buttons: a swipe never records "Got it" for an unseen answer.
    func gradeSwipes(cardID: String, revealed: Bool, fling: SwipeSide?, onGraded: @escaping (Bool) -> Void) -> some View {
        swipeActions(
            left: !revealed ? nil : SwipeAction(title: "Again", icon: "arrow.uturn.left", color: .falso, leavesCard: true) {
                ProgressStore.shared.review(cardID, known: false)
                onGraded(false)
            },
            right: !revealed ? nil : SwipeAction(title: "Got it", icon: "checkmark", color: .vero, leavesCard: true) {
                ProgressStore.shared.review(cardID, known: true)
                onGraded(true)
            },
            fling: fling
        )
    }
}

private struct GradeBar: View {
    @Binding var revealed: Bool
    /// Grading throws the card; its swipe action records the review.
    @Binding var fling: SwipeSide?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                if revealed {
                    Button { fling = .left } label: { Label("Again", systemImage: "arrow.uturn.left") }
                        .buttonStyle(SecondaryButtonStyle(tint: .falso))
                    Button { fling = .right } label: { Label("Got it", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle(tint: .vero))
                } else {
                    Button("Show") { withAnimation(.snappy) { revealed = true } }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .disabled(fling != nil)
    }
}
