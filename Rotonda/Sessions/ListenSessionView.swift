import MediaPlayer
import SwiftUI

/// Hands-free study for commuting, driving as a passenger, or a dark plane cabin: each
/// statement is read in Italian, then its translation, then the answer (and optionally why).
/// Keeps playing with the screen locked; lock-screen controls work too.
struct ListenSessionView: View {
    let source: QuestionSource

    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @State private var questions: [Question] = []
    @State private var index = 0
    /// The page in view; swiping, the buttons and auto-advance all move it.
    @State private var page: Int? = 0
    @State private var playing = false

    private var positionKey: String? {
        if case .chapter(let id) = source { "listen-\(id)" } else { nil }
    }

    var body: some View {
        @Bindable var preferences = preferences
        VStack(spacing: 0) {
            SessionTopBar(title: SessionTitle(session: .listen(source)),
                          position: index + 1, total: questions.count) { close() }
            if questions.isEmpty {
                ContentUnavailableView("Nothing to play", systemImage: "headphones")
            } else {
                // A native pager, each statement scrolling vertically on its own, so a drag
                // moves one axis only.
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(questions.indices, id: \.self) { position in
                                ScrollView {
                                    card(questions[position]).padding(16)
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(position)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $page)
                    .scrollIndicators(.hidden)
                }
                VStack(spacing: 14) {
                    HStack(spacing: 40) {
                        Button { step(-1) } label: { Image(systemName: "backward.fill").font(.title2) }
                            .disabled(index == 0)
                            .accessibilityLabel(Text("Previous"))
                        Button { playing ? pause() : play() } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill")
                                .font(.largeTitle).foregroundStyle(.white)
                                .frame(width: 84, height: 84).background(.signGradient, in: Circle())
                        }
                        .accessibilityLabel(playing ? Text("Pause") : Text("Play"))
                        Button { step(1) } label: { Image(systemName: "forward.fill").font(.title2) }
                            .disabled(index >= questions.count - 1)
                            .accessibilityLabel(Text("Next"))
                    }
                    HStack {
                        Toggle("Translation", isOn: $preferences.listenTranslation)
                        Toggle("Explanation", isOn: $preferences.listenExplanation)
                    }
                    .toggleStyle(.button)
                    .font(.subheadline)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(.bar)
            }
        }
        .readableWidth()
        .screenBackground()
        .swipeToClose(fromEdge: index == 0, perform: close)
        .onAppear(perform: load)
        .onChange(of: page) { _, value in
            guard let value, value != index, questions.indices.contains(value) else { return }
            index = value
            savePosition()
            if playing { play() } else { SpeechController.shared.stop() }
        }
        .onDisappear {
            SpeechController.shared.stop()
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            RemoteCommands.shared.clear()
        }
    }

    private func load() {
        switch source {
        case .chapter(let id):
            questions = ContentStore.shared.questions(chapter: id)
            index = min(progress.readingPosition("listen-\(id)"), max(questions.count - 1, 0))
            page = index
        default:
            questions = SessionBuilder.questions(for: source, count: 40)
        }
        RemoteCommands.shared.bind(play: { play() }, pause: { pause() }, next: { step(1) }, previous: { step(-1) })
    }

    private func play() {
        guard questions.indices.contains(index) else { return }
        playing = true
        let question = questions[index]
        let helper = preferences.helperLanguage
        var parts = [SpeechController.Part(text: question.textIT, language: "it-IT", pauseAfter: 0.9)]
        if preferences.listenTranslation {
            parts.append(.init(text: question.text(helper), language: helper.speechLanguage, pauseAfter: 0.9))
        }
        parts.append(.init(text: question.answer ? "Vero." : "Falso.", language: "it-IT", pauseAfter: 0.6))
        if preferences.listenExplanation && question.hasExplanation {
            // In the helper language when it has one, otherwise the Italian explanation.
            let explanation = question.explanation(helper)
            parts.append(explanation.isEmpty
                ? .init(text: question.italianExplanation, language: "it-IT", pauseAfter: 0.6)
                : .init(text: explanation, language: helper.speechLanguage, pauseAfter: 0.6))
        }
        updateNowPlaying(question)
        SpeechController.shared.speak(parts, key: speechKey(question)) {
            guard playing else { return }
            if index < questions.count - 1 {
                withAnimation(.snappy) { page = index + 1 }
            } else {
                playing = false
            }
        }
    }

    private func pause() {
        playing = false
        SpeechController.shared.stop()
    }

    private func step(_ delta: Int) {
        let target = min(max(index + delta, 0), questions.count - 1)
        guard target != index else { return }
        withAnimation(.snappy) { page = target }
    }

    /// Each statement has its own key, so only the page being read highlights its words.
    private func speechKey(_ question: Question) -> String { "listen-\(question.id)" }

    private func card(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let image = question.image { QuizImage(name: image, maxHeight: 150) }
            ItalianText(text: question.textIT, font: .title3.weight(.semibold), allowsLookup: false,
                        speechKey: speechKey(question), speechPart: 0)
            // The translation is the second part read aloud, when it is read.
            HelperTranslation(text: question.text(preferences.helperLanguage),
                              speechKey: preferences.listenTranslation ? speechKey(question) : nil, speechPart: 1)
            VerdictLabel(answer: question.answer)
        }
        .cardStyle(padding: 18)
    }

    private func savePosition() {
        if let positionKey { progress.setReadingPosition(index, for: positionKey) }
    }

    private func close() {
        playing = false
        SpeechController.shared.stop()
        dismiss()
    }

    private func updateNowPlaying(_ question: Question) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: question.textIT,
            MPMediaItemPropertyArtist: AppBrand.name,
            MPMediaItemPropertyAlbumTitle: Preferences.shared.string("Listen"),
        ]
    }
}

@MainActor
final class RemoteCommands {
    static let shared = RemoteCommands()
    private var targets: [(MPRemoteCommand, Any)] = []

    func bind(play: @escaping () -> Void, pause: @escaping () -> Void, next: @escaping () -> Void, previous: @escaping () -> Void) {
        clear()
        let center = MPRemoteCommandCenter.shared()
        let pairs: [(MPRemoteCommand, () -> Void)] = [
            (center.playCommand, play), (center.pauseCommand, pause),
            (center.nextTrackCommand, next), (center.previousTrackCommand, previous),
        ]
        for (command, action) in pairs {
            command.isEnabled = true
            let target = command.addTarget { _ in
                MainActor.assumeIsolated { action() }
                return .success
            }
            targets.append((command, target))
        }
    }

    func clear() {
        for (command, target) in targets { command.removeTarget(target) }
        targets = []
    }
}
