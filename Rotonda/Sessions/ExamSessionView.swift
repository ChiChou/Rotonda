import SwiftUI
import UIKit

/// Colours of the ministry's exam program, so the mock exam feels like the real screen.
private enum Official {
    static let background = Color(red: 0.83, green: 0.90, blue: 0.86)
    static let border = Color(red: 0.55, green: 0.62, blue: 0.58)
    static let mutedNumber = Color(red: 0.45, green: 0.52, blue: 0.50)
    static let current = Color(red: 0.70, green: 0.10, blue: 0.10)
    static let navy = Color(red: 0.10, green: 0.16, blue: 0.40)
    static let answered = Color(red: 0.72, green: 0.80, blue: 0.92)
}

/// The mock exam, laid out like the official exam program and shown in landscape like the
/// screen at the Motorizzazione: question groups, numbered boxes, "Domanda numero", square
/// V and F buttons, a countdown, a question list and arrow buttons. Everything is in Italian
/// with no translations, word lookup or explanations — exactly the conditions of the real
/// test. Swipe sideways on the question to move between questions.
struct ExamSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @State private var questions: [Question] = []
    @State private var answers: [Int: Bool] = [:]
    @State private var index = 0
    @State private var startedAt = Date.now
    @State private var hasStarted = false
    @State private var landscapeSettled = false
    @State private var record: ExamRecord?
    @State private var showsList = false
    @State private var confirmsSubmit = false
    @State private var confirmsAbort = false

    private let groupSize = 10

    var body: some View {
        GeometryReader { geometry in
            // The official exam is landscape only, on iPhone and iPad alike.
            let landscapeReady = landscapeSettled && geometry.size.width > geometry.size.height && !questions.isEmpty
            ZStack {
                Official.background.ignoresSafeArea()
                if landscapeReady && hasStarted {
                    if let record {
                        ExamResultView(record: record, questions: questions) { dismiss() }
                    } else {
                        exam
                    }
                } else if InterfaceOrientation.isPad && !questions.isEmpty && geometry.size.width <= geometry.size.height {
                    // A window the system cannot turn, such as Split View: the exam waits for landscape.
                    Label { Text(verbatim: "Ruota il dispositivo in orizzontale") } icon: { Image(systemName: "rotate.right") }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Official.navy)
                } else {
                    ProgressView()
                }
            }
            .background {
                ExamOrientationObserver { landscapeSettled = $0 }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: landscapeReady, initial: true) { _, ready in
                guard ready, !hasStarted else { return }
                startedAt = .now
                hasStarted = true
            }
        }
        .environment(\.colorScheme, .light)
        .statusBarHidden()
        .onAppear {
            if questions.isEmpty {
                questions = ContentStore.shared.examQuestions()
            }
        }
    }

    private var exam: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            VStack(spacing: wide ? 5 : 8) {
                groupTabs
                numberRow
                allQuestionsStrip
                Group {
                    if wide {
                        HStack(spacing: 8) {
                            imagePanel(maxHeight: .infinity).frame(width: geometry.size.width * 0.34)
                            VStack(spacing: 6) {
                                statementPanel.frame(maxHeight: .infinity)
                                answerPanel
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                if questions[index].image != nil { imagePanel(maxHeight: 230) }
                                statementPanel
                                answerPanel
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .id(questions[index].id)
                .transition(.opacity)
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    move(value.translation.width < 0 ? 1 : -1)
                })
                bottomBar
            }
            .padding(.horizontal, wide ? 16 : 10)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showsList) { questionList }
        // Handing in early corrects the test, like at the Motorizzazione.
        .confirmationDialog(Text(verbatim: "Vuoi consegnare la prova?"), isPresented: $confirmsSubmit, titleVisibility: .visible) {
            Button { submit() } label: { Text(verbatim: "Consegna e correggi") }
            Button(role: .cancel) {} label: { Text(verbatim: "Continua la prova") }
        } message: {
            Text(verbatim: "Domande senza risposta: \(questions.count - answers.count). Le domande senza risposta contano come errori.")
        }
        // Interrupted (a call, your stop): no score, but the answers given so far are kept.
        .confirmationDialog(Text(verbatim: "Vuoi interrompere la prova?"), isPresented: $confirmsAbort, titleVisibility: .visible) {
            Button(role: .destructive) { abort() } label: { Text(verbatim: "Interrompi") }
            Button(role: .cancel) {} label: { Text(verbatim: "Continua la prova") }
        } message: {
            Text(verbatim: "La prova non verrà valutata. Le risposte date finora vengono salvate: quelle sbagliate finiscono tra gli errori da ripassare.")
        }
    }

    // MARK: Navigation chrome

    private var groupTabs: some View {
        HStack(spacing: 4) {
            ForEach(0..<groupCount, id: \.self) { group in
                let first = group * groupSize + 1
                let last = min(first + groupSize - 1, questions.count)
                Button { index = group * groupSize } label: {
                    Text(verbatim: "Domande da \(first) a \(last)")
                        .font(.caption.weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(group == index / groupSize ? Official.current : Official.mutedNumber)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(Color.white, in: Rectangle())
                        .overlay(Rectangle().stroke(Official.border, lineWidth: group == index / groupSize ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var numberRow: some View {
        let group = index / groupSize
        let range = (group * groupSize)..<min(group * groupSize + groupSize, questions.count)
        return HStack(spacing: 3) {
            ForEach(Array(range), id: \.self) { offset in
                Button { index = offset } label: {
                    Text(verbatim: "\(offset + 1)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(offset == index ? Official.current : Official.mutedNumber)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(answers[questions[offset].id] == nil ? Color.white : Official.answered)
                        .overlay(Rectangle().stroke(Official.border, lineWidth: offset == index ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Question \(offset + 1)"))
            }
        }
    }

    private var allQuestionsStrip: some View {
        HStack(spacing: 1) {
            ForEach(questions.indices, id: \.self) { offset in
                Button { index = offset } label: {
                    // Longer exams (CQC: 70) shrink the numbers rather than wrapping them.
                    Text(verbatim: "\(offset + 1)")
                        .font(.system(size: 8, weight: offset == index ? .bold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(offset == index ? Official.current : Official.mutedNumber)
                        .frame(maxWidth: .infinity, minHeight: 14)
                        .background(answers[questions[offset].id] == nil ? Color.white : Official.answered)
                        .overlay(Rectangle().stroke(Official.border.opacity(0.6), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Question

    private func imagePanel(maxHeight: CGFloat) -> some View {
        ZStack {
            Color.white
            if let image = questions[index].image, let uiImage = QuizImage.load(image) {
                Image(uiImage: uiImage).resizable().scaledToFit().padding(12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: maxHeight)
    }

    private var statementPanel: some View {
        let question = questions[index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(verbatim: "Domanda numero").font(.subheadline)
                Text(verbatim: "\(index + 1)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Official.mutedNumber)
                    .frame(width: 38, height: 30)
                    .overlay(Rectangle().stroke(Official.border))
            }
            // Shrinks long statements to fit the box, as the official screen does, instead of scrolling.
            Text(question.textIT)
                .font(.system(size: 17, weight: .bold))
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            .frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity, alignment: .topLeading)
            .overlay(Rectangle().stroke(Official.border))
        }
        .padding(8)
        .foregroundStyle(Color.black)
        .background(Color.white, in: Rectangle())
    }

    private var answerPanel: some View {
        HStack(spacing: 44) {
            answerButton(true)
            answerButton(false)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white, in: Rectangle())
    }

    /// The square V / F buttons. The chosen one fills in, like the selection on the real screen.
    private func answerButton(_ value: Bool) -> some View {
        let selected = answers[questions[index].id] == value
        return Button {
            answers[questions[index].id] = selected ? nil : value
        } label: {
            VStack(spacing: 4) {
                Text(verbatim: value ? "Vero" : "Falso").font(.caption.weight(.semibold)).foregroundStyle(Color.black)
                ZStack {
                    Rectangle().fill(selected ? Official.navy : .white)
                    Rectangle().stroke(Official.navy, lineWidth: 2)
                    Circle().stroke(selected ? .white : Official.navy, lineWidth: 2).padding(9)
                    Text(verbatim: value ? "V" : "F")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(selected ? .white : Official.navy)
                }
                .frame(width: 50, height: 50)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel(Text(value ? "VERO" : "FALSO"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                let remaining = max(ContentStore.shared.examRules.seconds - Int(context.date.timeIntervalSince(startedAt)), 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "TEMPO A DISPOSIZIONE").font(.system(size: 7, weight: .medium)).foregroundStyle(Official.mutedNumber)
                    Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                        .font(.system(size: 24, weight: .regular).monospacedDigit())
                        .foregroundStyle(remaining < 120 ? Official.current : .black)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(width: 112)
                .overlay(Rectangle().stroke(Official.border))
                .onChange(of: remaining == 0) { _, expired in if expired { submit() } }
            }
            Spacer()
            Button { confirmsAbort = true } label: {
                Text(verbatim: "Interrompi").font(.subheadline.weight(.semibold)).foregroundStyle(Official.navy)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Color.white.opacity(0.7), in: Rectangle())
                    .overlay(Rectangle().stroke(Official.border))
            }
            .accessibilityLabel(Text("Quit exam"))
            Button { confirmsSubmit = true } label: {
                Text(verbatim: "Consegna").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Official.navy, in: Rectangle())
            }
            .accessibilityLabel(Text("Submit"))
            Button { showsList = true } label: {
                Image(systemName: "list.bullet")
                    .font(.title3.weight(.bold)).foregroundStyle(Official.navy)
                    .frame(width: 58, height: 40)
                    .background(Color.white.opacity(0.7), in: Rectangle())
                    .overlay(Rectangle().stroke(Official.border))
            }
            .accessibilityLabel(Text("All questions"))
            roundArrow("arrowtriangle.left", enabled: index > 0) { move(-1) }
                .accessibilityLabel(Text("Previous"))
            roundArrow("arrowtriangle.right", enabled: index < questions.count - 1) { move(1) }
                .accessibilityLabel(Text("Next"))
        }
    }

    private func roundArrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(Official.navy.opacity(enabled ? 1 : 0.3))
                .frame(width: 42, height: 42)
                .background(Circle().fill(.white.opacity(0.85)))
                .overlay(Circle().stroke(Official.border))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Riepilogo: every question with the answer given, tap to jump, and hand in.
    private var questionList: some View {
        NavigationStack {
            List {
                ForEach(questions.indices, id: \.self) { offset in
                    Button {
                        index = offset
                        showsList = false
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text(verbatim: "\(offset + 1)").font(.headline.monospacedDigit()).frame(width: 28)
                            Text(questions[offset].textIT).font(.subheadline).lineLimit(2).foregroundStyle(Color.primary)
                            Spacer()
                            Text(verbatim: answers[questions[offset].id].map { $0 ? "V" : "F" } ?? "–")
                                .font(.headline).foregroundStyle(Official.navy)
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: "Riepilogo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showsList = false } label: { Text(verbatim: "Chiudi") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showsList = false
                        confirmsSubmit = true
                    } label: { Text(verbatim: "Consegna") }
                }
            }
        }
    }

    private var groupCount: Int { (questions.count + groupSize - 1) / groupSize }

    private func move(_ delta: Int) {
        let target = index + delta
        guard questions.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.15)) { index = target }
    }

    /// Leaves without a score; answered statements still count as practice, so wrong ones
    /// become mistakes. Unanswered ones are not held against you.
    private func abort() {
        SpeechController.shared.stop()
        for question in questions {
            if let answer = answers[question.id] { progress.record(question, answer: answer) }
        }
        dismiss()
    }

    private func submit() {
        guard record == nil else { return }
        SpeechController.shared.stop()
        record = progress.saveExam(questions: questions, answers: answers,
                                   seconds: min(Int(Date.now.timeIntervalSince(startedAt)), ContentStore.shared.examRules.seconds))
    }
}

/// "Esito della prova": a full-screen verdict first — congratulations or not passed — then
/// every error with the answer given and the correct one. Italian, like the simulation.
/// Errors (unanswered included) are already in Mistakes, where the explanations are.
struct ExamResultView: View {
    let record: ExamRecord
    let questions: [Question]
    let done: () -> Void

    @State private var showsErrors = false
    @State private var appeared = false
    @State private var sharing: StoryMoment?

    private var wrong: [(offset: Int, element: Question)] {
        Array(questions.enumerated()).filter { record.answers[$0.element.id] != $0.element.answer }
    }

    var body: some View {
        NavigationStack {
            verdict
                .navigationDestination(isPresented: $showsErrors) { errorList }
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(\.colorScheme, .light)
    }

    private var verdict: some View {
        let tint = record.passed ? Color(red: 0.11, green: 0.54, blue: 0.29) : Color(red: 0.75, green: 0.16, blue: 0.13)
        return ZStack {
            tint.ignoresSafeArea()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 40) { headline; actions.frame(width: 300) }
                VStack(spacing: 28) { headline; actions }
            }
            .padding(24)
            .foregroundStyle(.white)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true } }
        .sensoryFeedback(record.passed ? .success : .error, trigger: appeared)
        .sheet(item: $sharing) { moment in
            CloseSheet(detents: [.large]) { StoryShareSheet(moment: moment) }
                .environment(\.colorScheme, .light)
        }
    }

    private var headline: some View {
        VStack(spacing: 10) {
            Image(systemName: record.passed ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.system(size: 72))
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
            Text(verbatim: record.passed ? "Complimenti!" : "Prova non superata")
                .font(.system(size: 34, weight: .heavy))
            Text(verbatim: record.passed ? "Esito: IDONEO" : "Esito: NON IDONEO")
                .font(.headline)
            Text(verbatim: "Risposte esatte \(record.correct) su \(questions.count). Errori \(record.errors) (massimo \(record.maxErrors))")
                .font(.subheadline).monospacedDigit()
            Text(verbatim: "Tempo impiegato \(Duration.seconds(record.durationSeconds).formatted(.time(pattern: .minuteSecond)))")
                .font(.subheadline).opacity(0.85).monospacedDigit()
        }
        .multilineTextAlignment(.center)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if record.passed {
                Button { sharing = .examPassed(errors: record.errors, seconds: record.durationSeconds) } label: {
                    Label { Text(verbatim: "Condividi") } icon: { Image(systemName: "square.and.arrow.up") }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Official.navy)
                }
                .buttonStyle(.plain)
            }
            if !wrong.isEmpty {
                Button { showsErrors = true } label: {
                    Text(verbatim: "Vedi gli errori (\(wrong.count))").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Official.navy)
                }
                .buttonStyle(.plain)
            }
            Button(action: done) {
                Text(verbatim: "Chiudi").font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 2))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            if !wrong.isEmpty {
                Text(verbatim: "Gli errori sono stati salvati: puoi ripassarli con le spiegazioni.")
                    .font(.caption).opacity(0.85).multilineTextAlignment(.center)
            }
        }
    }

    private var errorList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(wrong, id: \.element.id) { offset, question in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(offset + 1)").font(.headline.monospacedDigit()).foregroundStyle(Official.mutedNumber)
                            .frame(width: 30)
                        if let image = question.image, let uiImage = QuizImage.load(image) {
                            Image(uiImage: uiImage).resizable().scaledToFit().frame(width: 56, height: 56)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.textIT).font(.subheadline.weight(.semibold))
                            HStack(spacing: 14) {
                                Text(verbatim: "Risposta data: \(record.answers[question.id].map { $0 ? "Vero" : "Falso" } ?? "nessuna")")
                                    .foregroundStyle(Official.current)
                                Text(verbatim: "Risposta esatta: \(question.answer ? "Vero" : "Falso")")
                                    .foregroundStyle(Color(red: 0.11, green: 0.54, blue: 0.29))
                            }
                            .font(.caption.weight(.bold))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.white, in: Rectangle())
                    .overlay(Rectangle().stroke(Official.border.opacity(0.6)))
                }
            }
            .foregroundStyle(Color.black)
            .padding(16)
            .readableWidth()
        }
        .background(Official.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: "Errori"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: done) { Text(verbatim: "Chiudi") }
            }
        }
    }
}

struct ExamReviewSessionView: View {
    let examID: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(ProgressStore.self) private var progress

    var body: some View {
        if let record = progress.exams.first(where: { $0.id == examID }) {
            ExamResultView(record: record, questions: ContentStore.shared.questions(ids: progress.examQuestionIDs(record))) { dismiss() }
        } else {
            ContentUnavailableView("Exam not found", systemImage: "questionmark")
        }
    }
}

/// SwiftUI receives new dimensions at the start of a rotation. Reveal the exam only
/// after UIKit has also finished presenting and rotating its view controller.
private struct ExamOrientationObserver: UIViewControllerRepresentable {
    var onReady: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onReady = onReady
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onReady = onReady
    }

    final class Controller: UIViewController {
        var onReady: (Bool) -> Void = { _ in }
        private var appeared = false
        private var waiting = false
        private var lastReady: Bool?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appeared = true
            InterfaceOrientation.lock(.landscape)
            checkReadiness()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            checkReadiness()
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            publish(false)
            waitForTransition(coordinator)
        }

        private func checkReadiness() {
            guard appeared, !waiting else { return }
            if let coordinator = transitionCoordinator {
                waitForTransition(coordinator)
            } else {
                publishLandscape()
            }
        }

        private func waitForTransition(_ coordinator: UIViewControllerTransitionCoordinator) {
            guard !waiting else { return }
            waiting = true
            let accepted = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                waiting = false
                if appeared { publishLandscape() }
            }
            if !accepted {
                waiting = false
                if appeared { publishLandscape() }
            }
        }

        private func publishLandscape() {
            publish(view.window?.windowScene?.interfaceOrientation.isLandscape == true
                    && view.bounds.width > view.bounds.height)
        }

        private func publish(_ ready: Bool) {
            guard lastReady != ready else { return }
            lastReady = ready
            // Layout callbacks must not mutate SwiftUI state synchronously.
            DispatchQueue.main.async { [weak self] in self?.onReady(ready) }
        }
    }
}
