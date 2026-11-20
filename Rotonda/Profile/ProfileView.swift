import SwiftUI

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Preferences.self) private var preferences
    @Environment(ProgressStore.self) private var progress
    @State private var confirmsReset = false

    var body: some View {
        @Bindable var preferences = preferences
        NavigationStack {
            Form {
                Section {
                    NavigationLink { LicencePickerView() } label: {
                        LabeledContent("Licence") { Text(verbatim: preferences.licence.name) }
                    }
                    .accessibilityIdentifier("profileLicence")
                }

                Section("Progress") {
                    LabeledContent("Questions answered", value: "\(progress.stats.count) / \(ContentStore.shared.questionCount)")
                    LabeledContent("Bank mastered") { Text(progress.bankMastery, format: .percent.precision(.fractionLength(0))) }
                    if let accuracy = progress.recentAccuracy {
                        LabeledContent("Last 100 answers") { Text(accuracy, format: .percent.precision(.fractionLength(0))) }
                    }
                    LabeledContent("Words learned", value: "\(progress.learnedCount(prefix: "w:"))")
                    LabeledContent("Facts learned", value: "\(progress.learnedCount(prefix: "f:"))")
                    NavigationLink("By chapter") { ChapterProgressView() }
                }

                Section {
                    // The app's text and the translations under the Italian share one language.
                    Picker("Language", selection: $preferences.helperLanguage) {
                        ForEach(HelperLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
                    }
                    Toggle("Show translations", isOn: $preferences.showsTranslations)
                }


                Section("Study sessions") {
                    Picker("Session length", selection: $preferences.sessionLength) {
                        ForEach([5, 10, 20, 30], id: \.self) { Text("\($0)").tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        // Says a sample when let go, so the speed can be heard before a session.
                        Slider(value: $preferences.speechRate, in: 0.3...0.6) {
                            Text("Speaking speed")
                        } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                        onEditingChanged: { editing in
                            if !editing { SpeechController.shared.previewRate() }
                        }
                    }
                    Toggle("Listen: read translations", isOn: $preferences.listenTranslation)
                    Toggle("Listen: read explanations", isOn: $preferences.listenExplanation)
                }

                Section {
                    // Reopens the first-launch pages (welcome, language, licence, tour).
                    Button("Show welcome again") {
                        dismiss()
                        withAnimation { preferences.hasSeenGuide = false }
                    }
                    NavigationLink("Data sources & licences") { DataSourcesView() }
                }

                Section {
                    Button("Reset all progress", role: .destructive) { confirmsReset = true }
                }
            }
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.inline)
            .closeToolbar { dismiss() }
            .confirmationDialog("Reset all progress?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { progress.resetAll() }
            } message: {
                Text("Answers, memory cards and exam history will be deleted from this device.")
            }
        }
    }
}

private struct ChapterProgressView: View {
    var body: some View {
        List {
            Section {
                ForEach(ContentStore.shared.chapters) { ChapterProgressRow(chapter: $0) }
            } header: { Text("Chapters") }
        }
        .navigationTitle("By chapter")
    }
}

private struct DataSourcesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Questions come from the official Italian theory question banks for each licence. Translations and explanations were generated in advance and may contain mistakes — the Italian text is authoritative.")
                Text("Rotonda is an independent study app. It is not affiliated with or endorsed by the Italian Ministry of Infrastructure and Transport or the Motorizzazione Civile.")
                    .foregroundStyle(.secondary)
                Link("Language-Learning-decks: Italian CEFR estimates", destination: URL(string: "https://github.com/vbvss199/Language-Learning-decks")!)
                Link("Morph-it!: Italian inflected forms", destination: URL(string: "https://docs.sslmit.unibo.it/doku.php?id=resources:morph-it")!)
                Link("spaCy: Italian stop words", destination: URL(string: "https://github.com/explosion/spaCy/blob/master/spacy/lang/it/stop_words.py")!)
                Text(Bundle.main.url(forResource: "VocabularyDataNotices", withExtension: "txt")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
                    .font(.caption).textSelection(.enabled)
            }
            .padding(16)
        }
        .navigationTitle("Data sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The same profile entry point is available from every main tab.
private struct ProfileToolbarModifier: ViewModifier {
    @Environment(SessionCoordinator.self) private var sessions

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sessions.showsProfile = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel(Text("Progress and settings"))
                    .accessibilityIdentifier("profileSettings")
                }
            }
    }
}

extension View {
    func profileToolbar() -> some View {
        modifier(ProfileToolbarModifier())
    }
}
