import AVFoundation
import Combine
import Foundation

@MainActor
enum LockConfirmationSound {
    private static var player: AVAudioPlayer?

    private struct Beep {
        let start: Double
        let duration: Double
        let frequency: Double
        var secondFrequency: Double? = nil
        let amplitude: Double
    }

    /// Dijital anahtar READY olduğunda kilit teyit sesinden farklı tek kısa ses.
    /// Ambient kategori sessiz anahtara saygı gösterir.
    static func playConnectedTone() {
        play(makeWave(duration: 0.20, beeps: [
            Beep(start: 0, duration: 0.14, frequency: 1_046.5, amplitude: 0.12)
        ]))
    }

    /// Plays two short, stronger dual-tone honks through the iPhone speaker/audio route.
    /// The ambient session respects the device's silent switch.
    static func playDoubleBeep() {
        play(makeWave(duration: 0.48, beeps: [
            Beep(start: 0, duration: 0.16, frequency: 420, secondFrequency: 520, amplitude: 0.20),
            Beep(start: 0.26, duration: 0.16, frequency: 420, secondFrequency: 520, amplitude: 0.20)
        ]))
    }

    private static func play(_ data: Data) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let sound = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            sound.numberOfLoops = 0
            sound.prepareToPlay()
            player = sound
            sound.play()
        } catch {
            print("[BLE] lock confirmation sound failed: \(error.localizedDescription)")
        }
    }

    private static func makeWave(duration: Double, beeps: [Beep]) -> Data {
        let sampleRate = 22_050
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 2)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            var value = 0.0
            if let beep = beeps.first(where: { time >= $0.start && time < $0.start + $0.duration }) {
                let localTime = time - beep.start
                let fade = min(1, min(localTime / 0.008, (beep.duration - localTime) / 0.008))
                let first = sin(2 * Double.pi * beep.frequency * localTime)
                let second = beep.secondFrequency.map { sin(2 * Double.pi * $0 * localTime) } ?? 0
                value = (first + second) * beep.amplitude * max(0, fade)
            }
            var sample = Int16((value * Double(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }

        var wave = Data()
        wave.append(contentsOf: Array("RIFF".utf8))
        appendLE32(UInt32(36 + pcm.count), to: &wave)
        wave.append(contentsOf: Array("WAVEfmt ".utf8))
        appendLE32(16, to: &wave)
        appendLE16(1, to: &wave) // PCM
        appendLE16(1, to: &wave) // mono
        appendLE32(UInt32(sampleRate), to: &wave)
        appendLE32(UInt32(sampleRate * 2), to: &wave)
        appendLE16(2, to: &wave) // block alignment
        appendLE16(16, to: &wave)
        wave.append(contentsOf: Array("data".utf8))
        appendLE32(UInt32(pcm.count), to: &wave)
        wave.append(pcm)
        return wave
    }

    private static func appendLE16(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendLE32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

/// Explicit, on-device setup narration. It never opens the microphone or stores audio.
@MainActor
final class BLESetupVoiceGuide: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.47
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
