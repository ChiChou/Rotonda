import SwiftUI
import UIKit

@main
struct RotondaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = Preferences.shared
    @State private var progress = ProgressStore.shared
    @State private var sessions = SessionCoordinator()

    init() {
        // Someone updating with progress already on the device has no need for the guide.
        if UserDefaults.standard.object(forKey: "hasSeenGuide") == nil, !ProgressStore.shared.stats.isEmpty {
            Preferences.shared.hasSeenGuide = true
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .environment(progress)
                .environment(sessions)
                .environment(\.locale, preferences.locale)
                .tint(.signBlue)
        }
    }
}

enum AppTab: Hashable {
    case today, learn, quiz, memorize, search
}

/// Five destinations, each answering one intent:
/// Today — "I have a few minutes"; Learn — "I study in order"; Quiz — "test me, then simulate the exam";
/// Memorize — "drill what I must know"; Search — "what does this mean?".
struct RootView: View {
    @Environment(SessionCoordinator.self) private var sessions
    @Environment(Preferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.today
    @State var widgetDetail: WidgetDestination?

    var body: some View {
        @Bindable var sessions = sessions
        Group {
            if let error = ContentStore.shared.loadError {
                ContentUnavailableView("Study content unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                // The guide is the tabs' sibling, not their overlay: an overlay is rebuilt with the
                // tabs when the licence changes, which sent the guide back to its first page.
                ZStack {
                    TabView(selection: $tab) {
                        Tab("Today", systemImage: "sun.horizon.fill", value: AppTab.today) {
                            NavigationStack { TodayView() }
                        }
                        Tab("Learn", systemImage: "signpost.right.and.left.fill", value: AppTab.learn) {
                            ChaptersView()
                        }
                        Tab("Quiz", systemImage: "checkmark.circle.fill", value: AppTab.quiz) {
                            AdaptiveNavigation {
                                QuizHomeView()
                            } placeholder: {
                                LearnQuizChaptersView()
                            }
                        }
                        Tab("Memorize", systemImage: "rectangle.on.rectangle.angled", value: AppTab.memorize) {
                            AdaptiveNavigation(initialList: MemorizeView.allWords) {
                                WordBrowserView()
                            } root: {
                                MemorizeView()
                            } placeholder: {
                                SplitPlaceholder(title: "Nothing selected", systemImage: "character.book.closed")
                            }
                        }
                        Tab(value: AppTab.search, role: .search) {
                            AdaptiveNavigation {
                                SearchView()
                            } placeholder: {
                                SplitPlaceholder(title: "Nothing selected", systemImage: "magnifyingglass")
                            }
                        }
                    }
                    // Another licence is another bank: the tabs start over with its content.
                    .id(preferences.licence)
                    // The guide covers the tabs rather than replacing them, so they keep their state.
                    .accessibilityHidden(!preferences.hasSeenGuide)
                    if !preferences.hasSeenGuide { GuideView().transition(.opacity) }
                }
                // Presented outside the tabs' licence identity, so it stays open when the licence changes.
                .sheet(isPresented: $sessions.showsProfile) { ProfileView() }
            }
        }
        .fullScreenCover(item: $sessions.active, onDismiss: {
            InterfaceOrientation.unlock()
        }) { session in
            SessionHost(session: session)
                // Clear, so swiping a session closed shows the app underneath.
                .presentationBackground(.clear)
        }
        .onOpenURL(perform: open)
        .sheet(item: $widgetDetail) { destination in
            // Opened from the widget to read in full, so the sheet starts at full height.
            CloseSheet(detents: [.large]) {
                switch destination {
                case .statement(let question): QuestionDetailView(question: question)
                case .word(let word): WordDetailView(word: word).environment(\.alwaysShowsTranslations, true)
                case .session: EmptyView()
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                WidgetPublisher.importAnswers()
                WidgetPublisher.publish()
            case .background:
                WidgetPublisher.publish()
            default:
                break
            }
        }
        .onChange(of: preferences.helperLanguage) { WidgetPublisher.publish() }
        .onChange(of: sessions.active == nil) { _, ended in
            if ended { WidgetPublisher.publish() }
        }
    }
}

extension RootView {
    /// Widget taps: sessions open full screen; statements and words open in a sheet.
    func open(_ url: URL) {
        guard ContentStore.shared.loadError == nil, let destination = WidgetLink(url: url)?.destination else { return }
        widgetDetail = nil
        if case .session(let session) = destination {
            sessions.start(session)
        } else if sessions.active != nil {
            // A detail sheet can only appear once the open session has closed.
            sessions.active = nil
            Task { try? await Task.sleep(for: .milliseconds(600)); widgetDetail = destination }
        } else {
            widgetDetail = destination
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Version details live on the app's page in the Settings app, not in the app UI.
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String ?? "—"
        UserDefaults.standard.set("\(version) (\(build))", forKey: "app_version")
        UserDefaults.standard.set(ContentStore.shared.meta["content_version"] ?? "—", forKey: "content_version")
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        InterfaceOrientation.mask
    }
}

/// On iPhone the app is designed for portrait; the mock exam switches to landscape like the
/// computer screen at the real test. iPad supports every orientation and multitasking.
enum InterfaceOrientation {
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    static var mask: UIInterfaceOrientationMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    /// The app's own orientations: every one on iPad, portrait on iPhone.
    static var standard: UIInterfaceOrientationMask { isPad ? .all : .portrait }

    /// Locks the orientation, for the mock exam's landscape. `unlock()` returns to the standard.
    static func unlock() { lock(standard) }

    static func lock(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
        }
    }
}
