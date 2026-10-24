import AVFoundation
import Foundation

@MainActor
enum LockConfirmationSound {
    private static var player: AVAudioPlayer?

    /// Plays two short, soft tones through the iPhone speaker/audio route.
    /// The ambient session respects the device's silent switch.
    static func playDoubleBeep() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let sound = try AVAudioPlayer(data: makeWave(), fileTypeHint: AVFileType.wav.rawValue)
            sound.numberOfLoops = 0
            sound.prepareToPlay()
            player = sound
            sound.play()
        } catch {
            print("[BLE] lock confirmation sound failed: \(error.localizedDescription)")
        }
    }

    private static func makeWave() -> Data {
        let sampleRate = 22_050
        let duration = 0.42
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: sampleCount * 2)
        let beepDuration = 0.09
        let secondBeepStart = 0.20
        let frequency = 880.0

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let localTime: Double?
            if time < beepDuration {
                localTime = time
            } else if time >= secondBeepStart && time < secondBeepStart + beepDuration {
                localTime = time - secondBeepStart
            } else {
                localTime = nil
            }

            var value = 0.0
            if let localTime {
                let fade = min(1, min(localTime / 0.008, (beepDuration - localTime) / 0.008))
                value = sin(2 * Double.pi * frequency * localTime) * 0.16 * max(0, fade)
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
