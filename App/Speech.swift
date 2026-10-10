import SwiftUI
import AVFoundation
import TruthLensCore

enum SpeechSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var rate: Float {
        switch self {
        case .slow: 0.42
        case .normal: AVSpeechUtteranceDefaultSpeechRate
        case .fast: 0.58
        }
    }
}

enum SpeechVoices {
    /// Natural-sounding voices for the user's language. Novelty voices (macOS "Bells", "Whisper"...) are left out.
    static func available() -> [AVSpeechSynthesisVoice] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let inLanguage = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        let natural = inLanguage.filter {
            $0.identifier.hasPrefix("com.apple.voice.") || $0.identifier.hasPrefix("com.apple.ttsbundle.")
        }
        return (natural.isEmpty ? inLanguage : natural).sorted {
            $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name
        }
    }

    /// The chosen voice, or the best installed one when none is chosen.
    static func voice(id: String) -> AVSpeechSynthesisVoice? {
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return available().first ?? AVSpeechSynthesisVoice(language: Locale.current.identifier)
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "\(voice.name) (Premium)"
        case .enhanced: "\(voice.name) (Enhanced)"
        default: voice.name
        }
    }
}

/// On-device text-to-speech. Nothing is sent anywhere and it works offline.
@MainActor @Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    enum State { case idle, speaking, paused }

    private(set) var state: State = .idle
    private let synth = AVSpeechSynthesizer()
    private var current: ObjectIdentifier?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, voiceID: String, speed: SpeechSpeed) {
        let spoken = SpokenText.clean(text)
        guard !spoken.isEmpty else { return }
        synth.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = SpeechVoices.voice(id: voiceID)
        utterance.rate = speed.rate
        current = ObjectIdentifier(utterance)
        state = .speaking
        synth.speak(utterance)
    }

    func pause() { if synth.pauseSpeaking(at: .word) { state = .paused } }
    func resume() { if synth.continueSpeaking() { state = .speaking } }

    func stop() {
        current = nil
        synth.stopSpeaking(at: .immediate)
        state = .idle
    }

    // The previous utterance's "cancelled" callback can arrive after a new one has started,
    // so only the current utterance is allowed to reset the state.
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in if self.current == id { self.current = nil; self.state = .idle } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let id = ObjectIdentifier(u)
        Task { @MainActor in if self.current == id { self.current = nil; self.state = .idle } }
    }
}

/// Listen / pause / stop plus speed and voice, for any piece of drafted text.
struct ListenControls: View {
    let text: String
    @State private var speech = SpeechPlayer()
    @AppStorage("speechSpeed") private var speedRaw = SpeechSpeed.normal.rawValue
    @AppStorage("speechVoice") private var voiceID = ""

    private var speed: SpeechSpeed { SpeechSpeed(rawValue: speedRaw) ?? .normal }
    private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: primary) {
                switch speech.state {
                case .idle: Label("Listen", systemImage: "speaker.wave.2.fill")
                case .speaking: Label("Pause", systemImage: "pause.fill")
                case .paused: Label("Resume", systemImage: "play.fill")
                }
            }
            .disabled(isEmpty)

            if speech.state != .idle {
                Button { speech.stop() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            Spacer()
            Menu {
                Picker("Speed", selection: $speedRaw) {
                    ForEach(SpeechSpeed.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Voice", selection: $voiceID) {
                    Text("Automatic").tag("")
                    ForEach(SpeechVoices.available(), id: \.identifier) { v in
                        Text(SpeechVoices.label(v)).tag(v.identifier)
                    }
                }
            } label: {
                Label("Voice and speed", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .buttonStyle(.borderless)
        .onDisappear { speech.stop() }
        .onChange(of: text) { _, _ in speech.stop() }   // editing or regenerating makes the audio stale
    }

    private func primary() {
        switch speech.state {
        case .idle: speech.speak(text, voiceID: voiceID, speed: speed)
        case .speaking: speech.pause()
        case .paused: speech.resume()
        }
    }
}
