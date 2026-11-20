import AVFoundation
import SwiftUI
import Observation

/// On-device text to speech for Italian and the helper language. Works offline with the
/// system voices, keeps playing with the screen locked (for hands-free Listen sessions).
@MainActor
@Observable
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechController()

    private(set) var speakingKey: String?
    /// The word being said now, so the text on screen can highlight it.
    private(set) var spoken: SpokenRange?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Which part of the current request each utterance speaks.
    @ObservationIgnored private var parts: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var lastUtterance: AVSpeechUtterance?
    @ObservationIgnored private var completion: (() -> Void)?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    struct Part {
        let text: String
        let language: String
        var pauseAfter: TimeInterval = 0.5
    }

    /// A range in the text of one part of a speaking request (by its key and part number).
    struct SpokenRange: Equatable {
        let key: String
        let part: Int
        let range: NSRange
    }

    /// The range being spoken in part `part` of the request `key`, if any.
    func spokenRange(key: String?, part: Int = 0) -> NSRange? {
        guard let key, let spoken, spoken.key == key, spoken.part == part else { return nil }
        return spoken.range
    }

    func toggleItalian(_ text: String, key: String) {
        if speakingKey == key { stop() } else { speak([Part(text: text, language: "it-IT")], key: key) }
    }

    /// A short exam-style sentence at the current speaking speed, for the speed setting.
    func previewRate() {
        speak([Part(text: "Dare la precedenza ai veicoli che provengono da destra.", language: "it-IT")],
              key: "speech-rate-preview")
    }

    func speak(_ parts: [Part], key: String, completion: (() -> Void)? = nil) {
        stop()
        guard parts.contains(where: { !$0.text.isEmpty }) else { completion?(); return }
        activateAudio()
        speakingKey = key
        self.completion = completion
        let rate = Float(Preferences.shared.speechRate)
        // Part numbers follow the caller's list, so empty parts keep their place.
        for (number, part) in parts.enumerated() where !part.text.isEmpty {
            let utterance = AVSpeechUtterance(string: part.text)
            self.parts[ObjectIdentifier(utterance)] = number
            utterance.voice = AVSpeechSynthesisVoice(language: part.language)
            utterance.rate = rate
            utterance.postUtteranceDelay = part.pauseAfter
            synthesizer.speak(utterance)
            lastUtterance = utterance
        }
    }

    func stop() {
        completion = nil
        lastUtterance = nil
        parts.removeAll()
        spoken = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speakingKey = nil
    }

    private func activateAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard let key = self.speakingKey, let part = self.parts[id] else { return }
            self.spoken = SpokenRange(key: key, part: part, range: characterRange)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            if self.parts[id] == self.spoken?.part { self.spoken = nil }
            guard let last = self.lastUtterance, ObjectIdentifier(last) == id else { return }
            self.parts.removeAll()
            let completion = self.completion
            self.completion = nil
            self.lastUtterance = nil
            self.speakingKey = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            completion?()
        }
    }
}

/// Compact pronunciation action; its spoken label follows the same global locale as the app.
struct ItalianSpeechButton: View {
    let text: String
    let key: String
    private var speech = SpeechController.shared

    var body: some View {
        let speaking = speech.speakingKey == key
        Button { speech.toggleItalian(text, key: key) } label: {
            Image(systemName: speaking ? "stop.fill" : "speaker.wave.2")
                .font(.body)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(speaking ? Text("Stop") : Text("Listen"))
    }
}
