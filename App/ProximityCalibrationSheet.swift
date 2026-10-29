import SwiftUI

/// Yakınlık otomasyonu kalibrasyon rehberi.
///
/// Ölçüm mantığını değiştirmez; yalnızca kullanıcıya canlı RSSI, adım durumu ve
/// ölçüm ipuçlarını gösterir. Ölçümler `DashboardView` üzerinden alınır.
struct ProximityCalibrationSheet: View {
    let vin: String
    let currentRSSI: Int?
    let rssiAge: TimeInterval?
    let bleReady: Bool
    let nearSample: Int?
    let farSample: Int?
    let calibrationValid: Bool
    let profile: ProximityProfile
    let onCaptureNear: () -> Void
    let onCaptureFar: () -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isRSSIFresh: Bool {
        guard let rssiAge else { return false }
        return rssiAge < 15
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    liveSignalCard
                    stepsCard
                    tipsCard
                    if calibrationValid {
                        thresholdsCard
                    }
                    Text("Kalibrasyon telefon modeline ve kılıfa göre değişir. Telefonu her ölçümde aynı yerde (ör. ön cep) tutun.")
                        .font(.footnote)
                        .foregroundStyle(ToggTheme.muted)
                }
                .padding(20)
            }
            .background(ToggTheme.background.ignoresSafeArea())
            .navigationTitle("Yakınlık Kalibrasyonu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
        }
    }

    private var liveSignalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Canlı sinyal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ToggTheme.muted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentRSSI.map { "\($0)" } ?? "—")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(isRSSIFresh ? ToggTheme.teal : ToggTheme.muted)
                Text("dBm")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ToggTheme.muted)
                Spacer()
                signalBadge
            }

            Text(signalDescription)
                .font(.system(size: 11))
                .foregroundStyle(ToggTheme.muted)

            if !bleReady {
                Text("Araç bağlantısı hazır değil. Ölçüm için BLE bağlantısının READY olması gerekir.")
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.orange)
            } else if !isRSSIFresh {
                Text("Sinyal ölçümü eski. Araç uyanıkken birkaç saniye bekleyin.")
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(ToggTheme.surfaceVariant))
    }

    private var signalBadge: some View {
        let text: String
        let color: Color
        if !isRSSIFresh {
            text = "Veri yok"
            color = ToggTheme.muted
        } else if let currentRSSI, currentRSSI >= -60 {
            text = "Çok yakın"
            color = ToggTheme.green
        } else if let currentRSSI, currentRSSI >= -72 {
            text = "Yakın"
            color = ToggTheme.teal
        } else if let currentRSSI, currentRSSI >= -85 {
            text = "Orta"
            color = ToggTheme.orange
        } else {
            text = "Uzak"
            color = ToggTheme.muted
        }
        return Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    private var signalDescription: String {
        guard isRSSIFresh, currentRSSI != nil else { return "Sinyal gücü okunamıyor." }
        if let nearSample, let farSample, let current = currentRSSI {
            if current >= nearSample {
                return "Araç yanındayken alınan ölçüme yakın."
            }
            if current <= farSample {
                return "Uzakta alınan ölçüme yakın."
            }
            return "Ölçülen yakın ve uzak değerler arasında."
        }
        return "RSSI değeri negatiftir; 0'a yaklaştıkça sinyal güçlenir."
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adımlar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ToggTheme.muted)

            step(
                number: 1,
                title: "Araç yanında ölç",
                detail: "Telefonu cebinizde tutun, araç kapısının yanında durun ve 2 saniye bekleyip ölçün.",
                done: nearSample != nil,
                actionTitle: nearSample == nil ? "Yakında ölç" : "Yeniden ölç",
                action: onCaptureNear
            )
            step(
                number: 2,
                title: "Araçtan uzakta ölç",
                detail: "Aynı yönde 3–5 metre uzaklaşın, dönmeyin ve 2 saniye bekleyip ölçün.",
                done: farSample != nil,
                actionTitle: farSample == nil ? "Uzakta ölç" : "Yeniden ölç",
                action: onCaptureFar
            )
            step(
                number: 3,
                title: "Farkı doğrula",
                detail: "İki ölçüm arasında en az 14 dB fark olmalı. Fark küçükse telefon konumunu değiştirip tekrar ölçün.",
                done: calibrationValid,
                actionTitle: nil,
                action: nil
            )

            if nearSample != nil || farSample != nil {
                Button("Ölçümleri sıfırla", role: .destructive, action: onReset)
                    .font(.system(size: 12))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(ToggTheme.surfaceVariant))
    }

    private func step(
        number: Int,
        title: String,
        detail: String,
        done: Bool,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? ToggTheme.green : ToggTheme.outline.opacity(0.35))
                    .frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.bordered)
                        .tint(ToggTheme.teal)
                        .disabled(!bleReady || !isRSSIFresh)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nelere dikkat etmeli")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ToggTheme.muted)
            tip("Ölçüm sırasında telefonu elinizde sallamayın; vücut sinyali keser.")
            tip("Araç uyurken RSSI okunamaz; ölçümden önce bağlantının READY olması gerekir.")
            tip("Kılıf, el ve araç gövdesi 5–10 dB fark yaratabilir. Aynı koşullarda ölçün.")
            tip("Eşikler otomatik hesaplanır; profili değiştirerek tepki hızını ayarlayabilirsiniz.")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(ToggTheme.surfaceVariant))
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(ToggTheme.teal)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thresholdsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hesaplanan eşikler")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ToggTheme.muted)
            if let nearSample, let farSample {
                Text("Yakın \(nearSample) dBm · Uzak \(farSample) dBm")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Profil: \(profile.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(ToggTheme.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(ToggTheme.surfaceVariant))
    }
}
