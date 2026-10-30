import SwiftUI
import UIKit

/// Bas-konuş arayüzü. Yalnızca mikrofon/tanıma durumunu gösterir; niyet ayrıştırma
/// ve komut kapıları `DashboardView` tarafından uygulanır.
struct VoiceSheet: View {
    @ObservedObject var voice: VoiceAssistant
    let handler: (String) -> String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    #if DEBUG
    @State private var micTestResult: String?
    @State private var isTestingMic = false
    #endif

    private let examples = [
        "Şarjım ne kadar?",
        "Menzil kaç km?",
        "Kapılar kilitli mi?",
        "Lastik basınçları?",
        "Bagajı aç",
        "Yardım"
    ]

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    micButton
                    status
                    #if DEBUG
                    micTestSection
                    #endif
                    if !voice.transcript.isEmpty { transcriptCard }
                    if !voice.reply.isEmpty { replyCard }
                    exampleGrid
                    footnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            voice.onUtterance = handler
            VoiceLog.debug("sheet açıldı: handler bağlandı")
        }
        .onDisappear {
            VoiceLog.debug("sheet kapandı: ses oturumu temizleniyor")
            voice.end()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sesli Asistan")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                Text("Cihaz üstü Türkçe · internete gönderilmez")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ToggTheme.muted)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ToggTheme.muted)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ToggTheme.surfaceVariant))
            }
            .accessibilityLabel("Kapat")
        }
    }

    private var micButton: some View {
        Button {
            if voice.isListening {
                voice.stopListening()
            } else {
                voice.begin()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(ToggTheme.teal.opacity(0.35), lineWidth: 2)
                    .frame(width: 128, height: 128)
                    .scaleEffect(pulse ? 1.08 : 0.96)
                    .opacity(pulse ? 0.25 : 0.7)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: voice.isListening
                                ? [ToggTheme.pink, Color(hex: 0xB03A5B)]
                                : [ToggTheme.teal, Color(hex: 0x0E7C86)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)
                    .shadow(color: (voice.isListening ? ToggTheme.pink : ToggTheme.teal).opacity(0.4), radius: 18)

                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: 140)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(voice.isListening ? "Dinlemeyi durdur" : "Sesli komut söyle")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: reduceMotion) { reduced in
            if reduced {
                withAnimation(.linear(duration: 0.01)) { pulse = false }
            }
        }
    }

    private var status: some View {
        VStack(spacing: 8) {
            Text(voice.phase.message)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(voice.phase.isProblem ? ToggTheme.orange : ToggTheme.muted)

            if case .denied = voice.phase {
                Button("Ayarları aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ToggTheme.teal)
            }

            if voice.phase == .idle || voice.phase == .listening {
                Text("İpucu: “Evet” veya “tamam” deme; doğrudan komutunu söyle.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ToggTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    #if DEBUG
    private var micTestSection: some View {
        VStack(spacing: 7) {
            Button {
                guard !isTestingMic else { return }
                isTestingMic = true
                micTestResult = nil
                Task {
                    let result = await voice.runRecorderTest()
                    await MainActor.run {
                        micTestResult = result
                        isTestingMic = false
                    }
                }
            } label: {
                Label(
                    isTestingMic ? "Kaydediliyor… 5 sn konuş" : "Mikrofon kayıt testi (5 sn)",
                    systemImage: "waveform"
                )
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isTestingMic ? ToggTheme.orange : ToggTheme.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
            .disabled(isTestingMic)

            if let micTestResult {
                Text(micTestResult)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ToggTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }
    #endif

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("SÖYLEDİĞİN", icon: "waveform")
            Text(voice.transcript)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surface))
    }

    private var replyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("YANIT", icon: "speaker.wave.2.fill")
            Text(voice.reply)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(ToggTheme.teal.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ToggTheme.teal.opacity(0.35), lineWidth: 1))
        )
    }

    private var exampleGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Örnek komutlar")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ToggTheme.muted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        voice.submit(example)
                    } label: {
                        Text(example)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ToggTheme.teal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footnote: some View {
        Text("Ses kaydı saklanmaz. Kilit, bagaj ve cam komutları onay ister; kilit açma Face ID ile doğrulanır. Bagaj ve cam araçta doğrulanmadı (önizleme); klima servisi şu anda kullanılamıyor.")
            .font(.system(size: 10))
            .foregroundStyle(ToggTheme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func label(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 10, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(ToggTheme.teal)
    }
}
