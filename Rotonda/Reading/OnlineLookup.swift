import Network
import Observation
import SafariServices
import SwiftUI

/// Tracks connectivity so online extras appear only when they can work.
@MainActor
@Observable
final class NetworkStatus {
    static let shared = NetworkStatus()
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in NetworkStatus.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-status"))
    }
}

struct LookupSite: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let icon: String
    let url: URL

    static func sites(for query: String, language: HelperLanguage) -> [LookupSite] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        var sites: [LookupSite] = []
        let dictionary: String? = switch language {
        case .english: "iten"
        case .spanish: "ites"
        case .chinese: nil
        }
        if let dictionary, let url = URL(string: "https://www.wordreference.com/\(dictionary)/\(encoded)") {
            sites.append(LookupSite(id: "dictionary", title: "WordReference", icon: "character.book.closed", url: url))
        }
        if let url = URL(string: "https://it.wiktionary.org/wiki/\(encoded)") {
            sites.append(LookupSite(id: "wiktionary", title: "Wiktionary (IT)", icon: "text.book.closed", url: url))
        }
        return sites
    }
}

/// Rows that open online dictionaries in an in-app browser.
struct OnlineLookupSection: View {
    let query: String
    @Environment(Preferences.self) private var preferences
    @State private var openSite: LookupSite?
    @State private var requested: ExternalSite?
    private var network = NetworkStatus.shared

    init(query: String) { self.query = query }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Look it up online").font(.headline)
                Spacer()
                if !network.isOnline { Pill(Text("Offline"), tint: .secondary) }
            }
            .padding(.bottom, 6)
            if network.isOnline {
                let sites = LookupSite.sites(for: query, language: preferences.helperLanguage)
                ForEach(sites) { site in
                    Button { requested = ExternalSite(name: preferences.string(site.title), url: site.url) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: site.icon)
                                .foregroundStyle(Color.signBlue)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(site.title).foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(UIColor.tertiaryLabel))
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowButtonStyle(vertical: 0))
                    if site.id != sites.last?.id { Divider().padding(.leading, 36) }
                }
            }
        }
        .thirdPartyNotice($requested) { external in
            openSite = LookupSite.sites(for: query, language: preferences.helperLanguage).first { $0.url == external.url }
        }
        .sheet(item: $openSite) { site in SafariView(url: site.url).ignoresSafeArea() }
    }
}

/// A site outside the app, named for the notice shown before the first one opens.
struct ExternalSite: Identifiable {
    let name: String
    let url: URL
    var id: URL { url }
}

extension View {
    /// Before the first outside site opens, says it is not run by Rotonda and may show ads or set
    /// cookies. Set `pending` to ask; after Continue (once), `open` runs straight away.
    func thirdPartyNotice(_ pending: Binding<ExternalSite?>, open: @escaping (ExternalSite) -> Void) -> some View {
        modifier(ThirdPartyNotice(pending: pending, open: open))
    }
}

private struct ThirdPartyNotice: ViewModifier {
    @Binding var pending: ExternalSite?
    let open: (ExternalSite) -> Void
    @State private var asking: ExternalSite?
    @Environment(Preferences.self) private var preferences

    func body(content: Content) -> some View {
        content
            .onChange(of: pending?.id) {
                guard let site = pending else { return }
                pending = nil
                if preferences.hasSeenThirdPartyNotice { open(site) } else { asking = site }
            }
            .alert("Leaving Rotonda", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                   presenting: asking) { site in
                Button("Continue") {
                    preferences.hasSeenThirdPartyNotice = true
                    open(site)
                }
                Button("Cancel", role: .cancel) {}
            } message: { site in
                Text("\(site.name) is an outside website, not run by Rotonda. You might see ads or receive cookies there.")
            }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
