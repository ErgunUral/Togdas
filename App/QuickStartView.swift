import SwiftUI
import UIKit

/// "Hızlı Çalıştır": sürüş yetkilendirme akışı (Android `Garajm` paritesi).
///
/// Üç aşama: bağlantı + taze imzalı durum → sürüş yetkisi isteği (BLE kodu 14)
/// → hazır modu. Dürüstlük sınırları `QuickStartPolicy`de tanımlı:
/// - Geri sayım **yerel** sayaçtır; yetkinin araçta kalan süresi doğrulanamaz.
/// - "Hazır" yalnız imzalı telemetriden (powerState 4) gelir; ack yetmez.
/// - Komut kuyruğa alınmaz; otomatik retry yok (kapı: READY + taze telemetri).
struct QuickStartView: View {
    @EnvironmentObject private var ble: BleConnection
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case checking
        case authorizing
        case waitingReady
        case ready(String)
        case failed(String)
    }

    @State private var phase: Phase = .checking
    @State private var completedStages = 0
    @State private var remaining = Int(QuickStartPolicy.readyWindow)
    @State private var trace: [String] = []
    @State private var countdownTask: Task<Void, Never>?
    @State private var authorizationTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(message)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(phaseColor)
                        .fixedSize(horizontal: false, vertical: true)

                    stageList

                    if case .waitingReady = phase {
                        Text(QuickStartPolicy.countdownText(remaining: remaining))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    actionButton
                    notes
                    diagnostics
                }
                .padding(20)
            }
            .navigationTitle("Hızlı Çalıştır")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { cancel() }
                }
            }
        }
        .onAppear(perform: start)
        .onDisappear { stopTasks() }
        .onReceive(ble.$lastCommandReceipt) { handle($0) }
        .onReceive(ble.$telemetry) { telemetry in
            // Hazır modu yalnız imzalı telemetriden doğrulanır.
            guard case .waitingReady = phase,
                  QuickStartPolicy.isReadyPowerState(telemetry?.powerState) else { return }
            stopTasks()
            completedStages = 3
            phase = .ready("Araç hazır modda · imzalı telemetri (powerState 4).")
            addTrace("hazır modu imzalı telemetriyle doğrulandı")
        }
    }

    // MARK: - Görünüm parçaları

    private var message: String {
        switch phase {
        case .checking:
            return "Bağlantı ve güncel imzalı araç durumu kontrol ediliyor…"
        case .authorizing:
            return "Sürüş yetkisi isteği araca gönderildi; araç yanıtı bekleniyor."
        case .waitingReady:
            return "Araç isteği onayladı. Hazır modu imzalı telemetriden bekleniyor…"
        case .ready(let text):
            return text
        case .failed(let text):
            return text
        }
    }

    private var phaseColor: Color {
        switch phase {
        case .ready: return .green
        case .failed: return .red
        default: return .primary
        }
    }

    private var stageList: some View {
        VStack(spacing: 8) {
            ForEach(Array(QuickStartPolicy.stageTitles.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    Image(systemName: stageSymbol(index))
                        .foregroundStyle(index < completedStages ? .green : ToggTheme.muted)
                    Text(title)
                        .font(.callout)
                    Spacer()
                    Text(stageStatus(index))
                        .font(.caption)
                        .foregroundStyle(ToggTheme.muted)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ToggTheme.outline.opacity(0.45))
                )
            }
        }
    }

    private func stageSymbol(_ index: Int) -> String {
        if index < completedStages { return "checkmark.circle.fill" }
        if index == completedStages, isRunning { return "circle.dotted" }
        return "circle"
    }

    private func stageStatus(_ index: Int) -> String {
        if index < completedStages { return "Tamam" }
        if index == completedStages, isRunning { return "Sürüyor" }
        if case .failed = phase, index == completedStages { return "Durdu" }
        return "Bekliyor"
    }

    private var isRunning: Bool {
        switch phase {
        case .authorizing, .waitingReady: return true
        default: return false
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch phase {
        case .failed, .checking:
            Button("Tekrar dene") { start() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        case .authorizing, .waitingReady:
            Button("İptal") { cancel() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        case .ready:
            EmptyView()
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start/Stop ve fren işlemlerini siz yaparsınız. Kapatmak, araçta kabul edilmiş yetkiyi geri almaz.")
            Text("Yetkinin kalan süresi araçtan doğrulanamaz; yukarıdaki sayaç yalnız istek anından itibaren yerel ölçümdür.")
            Text("Araçtan imzalı durum gelmezse \"hazır\" denmez; istek onayı hazır moda geçiş değildir.")
        }
        .font(.caption)
        .foregroundStyle(ToggTheme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var diagnostics: some View {
        DisclosureGroup("Hızlı Çalıştır tanısı") {
            VStack(alignment: .leading, spacing: 4) {
                if trace.isEmpty {
                    Text("Kayıt yok.").font(.caption2).foregroundStyle(ToggTheme.muted)
                }
                ForEach(Array(trace.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Kopyala") {
                    UIPasteboard.general.string = trace.joined(separator: "\n")
                }
                .font(.caption)
                .disabled(trace.isEmpty)
            }
            .padding(.top, 4)
        }
        .font(.footnote)
    }

    // MARK: - Akış

    private func start() {
        stopTasks()
        completedStages = 0
        remaining = Int(QuickStartPolicy.readyWindow)
        trace.removeAll()

        if QuickStartPolicy.isReadyPowerState(ble.telemetry?.powerState) {
            completedStages = 3
            phase = .ready("Araç zaten hazır modda; yetki isteği gönderilmedi.")
            addTrace("başlangıç: powerState 4")
            return
        }

        if let rejection = BLECommandPolicy.rejection(code: 14,
                                                     linkReady: ble.state.isReady,
                                                     telemetry: ble.telemetry) {
            phase = .failed(rejection.message)
            addTrace("kapı reddi: \(rejection.diagnosticCode)")
            return
        }

        guard ble.driveAuthorize() else {
            phase = .failed(ble.lastEvent.isEmpty
                            ? "Sürüş yetkisi isteği gönderilemedi."
                            : ble.lastEvent)
            addTrace("komut verilemedi")
            return
        }

        completedStages = 1
        phase = .authorizing
        addTrace("sürüş yetkisi isteği gönderildi (kod 14)")

        let window = QuickStartPolicy.authorizationWindow
        authorizationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard case .authorizing = phase else { return }
            phase = .failed("Araç \(Int(window)) saniye içinde yanıt vermedi; istek iletilmemiş olabilir. Sinyal zayıfsa tekrar deneyin.")
            addTrace("ack zaman aşımı")
        }
    }

    private func handle(_ receipt: BLECommandReceipt?) {
        guard let receipt, receipt.code == 14 else { return }
        switch receipt.phase {
        case .acknowledged, .verified:
            guard case .authorizing = phase else { return }
            completedStages = max(completedStages, 2)
            phase = .waitingReady
            addTrace("araç isteği onayladı (ack)")
            startCountdown()
        case .failed:
            guard phase == .authorizing || phase == .waitingReady else { return }
            stopTasks()
            completedStages = max(completedStages, 1)
            phase = .failed(receipt.detail
                            ?? receipt.failureReason?.explanation
                            ?? "Komut tamamlanmadı.")
            addTrace("başarısız: \(receipt.failureReason?.title ?? "bilinmiyor")")
        default:
            return
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        remaining = Int(QuickStartPolicy.readyWindow)
        countdownTask = Task { @MainActor in
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining -= 1
            }
            guard case .waitingReady = phase else { return }
            phase = .failed(QuickStartPolicy.readyTimeoutText)
            addTrace("hazır modu zaman aşımı")
        }
    }

    private func cancel() {
        stopTasks()
        addTrace("kullanıcı kapattı; araçta kabul edilmiş yetki geri alınmaz")
        dismiss()
    }

    private func stopTasks() {
        countdownTask?.cancel()
        countdownTask = nil
        authorizationTask?.cancel()
        authorizationTask = nil
    }

    /// Hem ekran izi hem telefon tanısı: saha testinde akışın hangi aşamada
    /// durduğu plist'ten okunabilsin.
    private func addTrace(_ message: String) {
        let stamp = TurkishFormat.date(Date(), format: "HH:mm:ss")
        trace.append("\(stamp) · \(message)")
        ble.recordDiagnostic("quick_start · \(message)")
    }
}
