import Foundation
import Observation

enum AppBrand {
    static let name = "Rotonda"
}

enum TranslationMode: String, CaseIterable, Identifiable {
    case shown, tapToReveal, hidden
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .shown: "Always show"
        case .tapToReveal: "Tap to reveal"
        case .hidden: "Italian only"
        }
    }
}

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Starts as the app's UI language. Choosing another one in the app also stores it as the
    /// app's language, the setting the Settings app shows, so system-drawn text and the widgets
    /// follow at the next launch; the app's own text follows at once through `locale`.
    var helperLanguage: HelperLanguage {
        didSet {
            guard helperLanguage != oldValue else { return }
            defaults.set([helperLanguage.rawValue], forKey: "AppleLanguages")
        }
    }

    /// The device's locale in the chosen language, for the SwiftUI environment.
    var locale: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: helperLanguage.rawValue)
        return Locale(components: components)
    }

    /// A string in the chosen language, for text that does not pass through a SwiftUI `Text`.
    func string(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
    /// The licence being studied. Content, progress figures and the mock exam follow it;
    /// answers are kept per question, so they carry over to licences that share questions.
    var licence: Licence {
        didSet {
            guard licence != oldValue else { return }
            defaults.set(licence.rawValue, forKey: "licence")
            ContentStore.shared.licence = licence
            ProgressStore.shared.licenceDidChange()
            WidgetPublisher.publish()
        }
    }

    var translationMode: TranslationMode { didSet { defaults.set(translationMode.rawValue, forKey: "translationMode") } }
    var showsTranslations: Bool {
        get { translationMode == .shown }
        set { translationMode = newValue ? .shown : .hidden }
    }

    var sessionLength: Int { didSet { defaults.set(sessionLength, forKey: "sessionLength") } }
    var speechRate: Double { didSet { defaults.set(speechRate, forKey: "speechRate") } }
    var listenTranslation: Bool { didSet { defaults.set(listenTranslation, forKey: "listenTranslation") } }
    var listenExplanation: Bool { didSet { defaults.set(listenExplanation, forKey: "listenExplanation") } }
    /// The notice about third-party sites shows before the first one opens, then not again.
    var hasSeenThirdPartyNotice: Bool { didSet { defaults.set(hasSeenThirdPartyNotice, forKey: "hasSeenThirdPartyNotice") } }

    /// The first-launch guide shows until it is finished; the profile sheet can reopen it.
    var hasSeenGuide: Bool { didSet { defaults.set(hasSeenGuide, forKey: "hasSeenGuide") } }

    private init() {
        // The app's UI language (from AppleLanguages) names the helper language; the two are one setting.
        helperLanguage = Bundle.main.preferredLocalizations.first.flatMap(HelperLanguage.init(localization:)) ?? .english
        licence = defaults.string(forKey: "licence").flatMap(Licence.init) ?? .ab
        translationMode = defaults.string(forKey: "translationMode").flatMap(TranslationMode.init) ?? .shown
        sessionLength = defaults.object(forKey: "sessionLength") as? Int ?? 10
        speechRate = defaults.object(forKey: "speechRate") as? Double ?? 0.46
        listenTranslation = defaults.object(forKey: "listenTranslation") as? Bool ?? true
        listenExplanation = defaults.bool(forKey: "listenExplanation")
        hasSeenThirdPartyNotice = defaults.bool(forKey: "hasSeenThirdPartyNotice")
        hasSeenGuide = defaults.bool(forKey: "hasSeenGuide")
    }
}
