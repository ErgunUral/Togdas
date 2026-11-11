// Dijital anahtar kurulum rehberi (5 adım + seslendirme)
// DashboardView'dan ayrıldı (2026-11-12) — yalnız taşıma; davranış değişikliği yok.

import SwiftUI

// MARK: - Giriş ekranı

struct BLESetupGuideStep: Identifiable {
    let number: Int
    let title: String
    let narration: String
    var id: Int { number }

    static let all: [BLESetupGuideStep] = [
        .init(number: 1, title: "Aracın yanına gel", narration: "Aracın yanında dur. iPhone Bluetooth'unun açık olduğundan emin ol ve Toqdas uygulamasını ekranda açık tut."),
        .init(number: 2, title: "Bağlantıyı başlat", narration: "Dashboard'daki Bluetooth Dijital Anahtar kartında bağlan düğmesine dokun. Araç bulunup GATT servisleri keşfedilirken telefonu araçtan uzaklaştırma."),
        .init(number: 3, title: "Eşleştirmeyi araçtan başlat", narration: "Araç ekranı dijital anahtar eşleştirmesi isterse işlemi araç ekranından başlat. iPhone'da bir eşleştirme kodu görünürse kodları karşılaştırıp onayla."),
        .init(number: 4, title: "Kimlik doğrulamayı bekle", narration: "Sertifika ve imzalı kimlik doğrulaması sürerken uygulama ekranında kal. Araç anahtarı eksik uyarısı görünürse araca komut gönderilmez."),
        .init(number: 5, title: "Yeşil durumu doğrula", narration: "Bluetooth Dijital Anahtar kartında yeşil Bağlı, Komut hazır yazısını bekle. Komutlar yalnızca bağlantı hazır ve imzalı araç verisi güncelse gönderilebilir. Arka planda araç komutu gönderilmez.")
    ]
}

struct BLESetupGuideSheet: View {
    @ObservedObject var ble: BleConnection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = BLESetupVoiceGuide()
    @State private var stepIndex = 0

    private var step: BLESetupGuideStep { BLESetupGuideStep.all[stepIndex] }

    private var liveStatus: String {
        if ble.needsRepair { return "iPhone ve araç eşleşmesi sıfırlanmalı." }
        if ble.pairingRequired { return "Araç anahtarı eksik; eşleştirmeyi araç ekranından başlat." }
        if ble.state.isReady { return "Bağlı · Komut hazır" }
        return ble.state.description
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ToggTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("ADIM \(step.number) / \(BLESetupGuideStep.all.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(ToggTheme.teal)
                        Spacer()
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(ble.state.isReady ? ToggTheme.green : ToggTheme.teal)
                    }

                    Text(step.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(step.narration)
                        .font(.system(size: 15))
                        .foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Circle().fill(ble.state.isReady ? ToggTheme.green : ToggTheme.orange)
                            .frame(width: 8, height: 8)
                        Text(liveStatus)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ble.state.isReady ? ToggTheme.green : ToggTheme.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))

                    Button {
                        speaker.speak(step.narration)
                    } label: {
                        Label("Bu adımı seslendir", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.teal))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button("Önceki") {
                            speaker.stop()
                            stepIndex = max(0, stepIndex - 1)
                        }
                        .disabled(stepIndex == 0)

                        Button(stepIndex == BLESetupGuideStep.all.count - 1 ? "Baştan dinle" : "Sonraki · dinle") {
                            let nextIndex = stepIndex == BLESetupGuideStep.all.count - 1 ? 0 : stepIndex + 1
                            stepIndex = nextIndex
                            speaker.speak(BLESetupGuideStep.all[nextIndex].narration)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ToggTheme.teal)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("Ses cihazda üretilir. Mikrofon açılmaz; ses kaydı veya transkript gönderilmez.")
                        .font(.system(size: 10))
                        .foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Dijital anahtar kurulumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .onDisappear { speaker.stop() }
    }
}
