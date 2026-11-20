import Foundation
import Observation

/// Every focused activity in the app. Sessions open full screen from any tab, so a
/// 3-minute commute session is one tap away and always ends back where it started.
enum StudySession: Codable, Hashable, Identifiable {
    /// Study a few statements with their answers, then quiz exactly those — repeat.
    case learnQuiz(chapter: Int)
    case read(chapter: Int)
    case practice(QuestionSource)
    case words(WordSource)
    case wordQuiz(WordSource)
    case facts(FactSource)
    case numberQuiz(FactSource)
    case review
    case listen(QuestionSource)
    case exam
    case examReview(examID: Int)

    var id: Self { self }

    /// Sessions worth offering under "Continue" on Today.
    var isResumable: Bool {
        switch self {
        case .exam, .examReview, .review: false
        // Quick sessions draw a fresh set each time and already have their own tiles on Today.
        case .practice(.quickMix), .words(.ladder), .wordQuiz(.ladder), .listen(.quickMix): false
        // Drawn fresh from progress each time and started from their own card on Today.
        case .words(.reach), .words(.mistakes), .wordQuiz(.reach), .wordQuiz(.mistakes): false
        // Opened from the widget's deck, which is replaced whenever the widget refreshes.
        case .practice(.statements): false
        default: true
        }
    }
}

enum QuestionSource: Codable, Hashable {
    case chapter(Int)
    case mistakes
    case chapterMistakes(Int)
    case quickMix
    case bookmarks
    case word(Int)
    case fact(String)
    case group(Int)
    case picture(image: String, chapter: Int?)
    /// Random statements that come with a picture.
    case signs
    /// Fixed statements in order, such as the deck opened from the Home Screen widget.
    case statements([Int])
}

enum WordSource: Codable, Hashable {
    case ladder
    case chapter(Int)
    case examLanguage
    /// The words that open the most exam questions.
    case reach
    /// Words from questions answered wrong.
    case mistakes
}

enum FactSource: Codable, Hashable {
    case due
    case deck(FactDeck)
    case chapter(Int)
}

@MainActor
@Observable
final class SessionCoordinator {
    var active: StudySession?
    /// Progress and settings, opened from any tab.
    var showsProfile = false

    func start(_ session: StudySession) {
        ProgressStore.shared.setLastSession(session)
        active = session
    }
}

import SwiftUI

extension StudySession {
    var icon: String {
        switch self {
        case .learnQuiz: "graduationcap"
        case .read: "book.pages"
        case .practice: "checkmark.circle"
        case .words: "character.book.closed"
        case .wordQuiz: "character.textbox"
        case .facts: "number.square"
        case .numberQuiz: "number.circle"
        case .review: "arrow.triangle.2.circlepath"
        case .listen: "headphones"
        case .exam, .examReview: "stopwatch"
        }
    }

    var hasChapterTitle: Bool { chapterID != nil }

    /// The chapter a session belongs to, when its title names one.
    var chapterID: Int? {
        switch self {
        case .learnQuiz(let id), .read(let id),
             .practice(.chapter(let id)), .practice(.chapterMistakes(let id)),
             .listen(.chapter(let id)), .listen(.chapterMistakes(let id)),
             .words(.chapter(let id)), .wordQuiz(.chapter(let id)),
             .facts(.chapter(let id)), .numberQuiz(.chapter(let id)): id
        default: nil
        }
    }

    /// The activity alone, for places where the chapter is already named nearby.
    var isReading: Bool {
        if case .read = self { true } else { false }
    }

    /// A session built from one fact deck, whose name is already in the header.
    var factDeck: FactDeck? {
        switch self {
        case .facts(.deck(let deck)), .numberQuiz(.deck(let deck)): deck
        default: nil
        }
    }

    var activityTitle: Text {
        switch self {
        case .learnQuiz: Text("Learn & quiz")
        case .read: Text("Read with answers")
        case .practice(.chapterMistakes), .listen(.chapterMistakes): Text("Fix mistakes")
        case .practice: Text("Quiz")
        case .listen: Text("Listen")
        case .words: Text("Key words")
        case .wordQuiz: Text("Word quiz")
        case .facts: Text("Key facts")
        case .numberQuiz: Text("Numbers quiz")
        case .review: Text("Review")
        case .exam: Text("Mock exam")
        case .examReview: Text("Exam review")
        }
    }

    func title(language: HelperLanguage, showsTranslations: Bool? = nil) -> Text {
        let content = ContentStore.shared
        func chapterName(_ id: Int) -> String {
            guard let chapter = content.chapter(id) else { return "" }
            return (showsTranslations ?? Preferences.shared.showsTranslations) ? chapter.shortTitle(language) : chapter.shortIT
        }
        switch self {
        case .learnQuiz(let chapter): return Text("Learn & quiz: \(chapterName(chapter))")
        case .read(let chapter): return Text("Read: \(chapterName(chapter))")
        case .practice(let source), .listen(let source):
            let verb = if case .listen = self { Text("Listen") } else { Text("Quiz") }
            switch source {
            case .chapter(let id): return Text("\(verb): \(chapterName(id))")
            case .chapterMistakes(let id): return Text("\(verb): Mistakes: \(chapterName(id))")
            case .mistakes: return Text("\(verb): Mistakes")
            case .quickMix: return Text("\(verb): Mixed questions")
            case .bookmarks: return Text("\(verb): Saved questions")
            case .word(let id): return Text("\(verb): \(content.word(id)?.lemma ?? "")")
            case .fact: return Text("\(verb): Fact questions")
            case .group, .picture: return Text("\(verb): Sign")
            case .signs: return Text("\(verb): Signs & pictures")
            case .statements: return Text(verbatim: "Vero o falso?")
            }
        case .words(let source), .wordQuiz(let source):
            if case .wordQuiz = self {
                switch source {
                case .ladder: return Text("Word quiz")
                case .chapter(let id): return Text("Word quiz: \(chapterName(id))")
                case .examLanguage: return Text("Word quiz: Exam language")
                case .reach: return Text("Word quiz: Next words")
                case .mistakes: return Text("Word quiz: Words from mistakes")
                }
            }
            switch source {
            case .ladder: return Text("Words: Key word ladder")
            case .chapter(let id): return Text("Words: \(chapterName(id))")
            case .examLanguage: return Text("Words: Exam language")
            case .reach: return Text("Words: Next words")
            case .mistakes: return Text("Words: Words from mistakes")
            }
        case .numberQuiz(let source):
            switch source {
            case .due: return Text("Numbers quiz")
            case .deck(let deck): return Text("Numbers quiz: \(Text(deck.title))")
            case .chapter(let id): return Text("Numbers quiz: \(chapterName(id))")
            }
        case .facts(let source):
            switch source {
            case .due: return Text("Facts: Due")
            case .deck(let deck): return Text("Facts: \(Text(deck.title))")
            case .chapter(let id): return Text("Facts: \(chapterName(id))")
            }
        case .review: return Text("Review")
        case .exam: return Text("Mock exam")
        case .examReview: return Text("Exam review")
        }
    }
}

struct SessionTitle: View {
    let session: StudySession
    @Environment(Preferences.self) private var preferences
    /// Centred in the session bar, leading in cards such as Continue.
    @Environment(\.multilineTextAlignment) private var textAlignment

    var body: some View {
        if let chapter = session.chapterID.flatMap({ ContentStore.shared.chapter($0) }) {
            // Two short lines: what you are doing, then where, as the chapter lists show it.
            // The full and translated chapter title is read out by VoiceOver.
            VStack(alignment: textAlignment == .center ? .center : .leading, spacing: 3) {
                // Reading shows statements with their answers; the screen says what it is, so the
                // header names only the chapter.
                if !session.isReading {
                    session.activityTitle
                        .lineLimit(1)
                }
                HStack(alignment: session.isReading ? .top : .center, spacing: 5) {
                    SignBadge(text: "\(chapter.position)", size: 17)
                    Text(chapter.topicIT)
                        .font(session.isReading ? .subheadline.weight(.semibold) : .caption)
                        .foregroundStyle(session.isReading ? Color.primary : Color.secondary)
                        // Alone in the header, a long topic may take the second line.
                        .lineLimit(session.isReading ? 2 : 1)
                        .truncationMode(.tail)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.activityTitle
                + Text(verbatim: ", \(chapter.position) \(chapter.shortIT), \(chapter.shortTitle(preferences.helperLanguage))"))
        } else {
            session.title(language: preferences.helperLanguage)
                .lineLimit(1)
        }
    }
}
