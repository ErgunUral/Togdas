import SwiftUI

struct CommandView: View {
    let vehicle: Vehicle
    let api: ToggAPI

    @EnvironmentObject private var ble: BleConnection
    @State private var message = ""
    @State private var error: String?
    @State private var busy = false
    @State private var pending: PendingCommand?
    @State private var showChannels = false
    @State private var ownerTransferRequired = false

    enum PendingCommand: String, Identifiable {
        case unlock, lock, trunkOpen, trunkClose, driveAuthorize
        var id: String { rawValue }
        var title: String {
            switch self {
            case .unlock: return "Kilidi aç"
            case .lock: return "Kilitle"
            case .trunkOpen: return "Bagajı aç"
            case .trunkClose: return "Bagajı kapat"
            case .driveAuthorize: return "Sürüş yetkilendir"
            }
        }
        var detail: String {
            switch self {
            case .driveAuthorize: return "Araç sürüş için yetkilendirilecek."
            case .lock: return "Önce cam kapatma, ardından kapı kilitleme komutu gönderilecek. Cam konumu doğrulanamıyor; çevrede engel olmadığından emin olun."
            default: return "\(title) komutu araca gönderilecek."
            }
        }
    }

    private var canAuthenticate: Bool { ble.state.isCertificate || ble.state.isChallenge }
    private var commandsEnabled: Bool { ble.state.isReady && !busy }

    var body: some View {
        List {
            Section("Araç") {
                Text(vehicle.title)
                Text(vehicle.vin).font(.caption).monospaced()
            }

            Section("Bluetooth") {
                Text(ble.state.description)
                if ble.needsRepair {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Eşleşme sıfırlanmalı", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.bold()).foregroundStyle(.orange)
                        Text("1. iPhone: Ayarlar > Bluetooth > araç kaydını unut.\n2. Araç ekranı: telefonu/eşleşmeyi kaldır.\n3. İki cihazı yeniden başlat.\n4. Bu ekrandan yeniden bağlan.")
                            .font(.caption)
                    }
                }
                Button(ble.state.isDisconnected ? "Araç servisine bağlan" : "Bağlantıyı kes") {
                    ble.state.isDisconnected ? ble.start(vin: vehicle.vin) : ble.disconnect()
                }
                if !ble.channels.isEmpty {
                    DisclosureGroup("Kanallar (\(ble.channels.count))", isExpanded: $showChannels) {
                        ForEach(ble.channels, id: \.self) { Text($0).font(.caption2).monospaced() }
                    }
                }
            }

            Section("Dijital anahtar") {
                if let key = PhoneKeyStore.publicKeyHex(for: vehicle.vin) {
                    Text("Telefon anahtarı: \(key.prefix(16))…")
                        .font(.caption).monospaced().textSelection(.enabled)
                }
                if !ble.phonePublicKeyHex.isEmpty {
                    Text("Aktif anahtar: \(ble.phonePublicKeyHex.prefix(16))…")
                        .font(.caption).monospaced()
                }
                if !ble.carPublicKeyHex.isEmpty {
                    Text("Araç anahtarı: \(ble.carPublicKeyHex.prefix(16))…")
                        .font(.caption).monospaced()
                }
                Button {
                    Task { await authenticate() }
                } label: {
                    Label("Sertifikayı hazırla ve araca sun", systemImage: "key.horizontal")
                }
                .disabled(!canAuthenticate || busy)
                if !canAuthenticate && !ble.state.isReady {
                    Text("Bu işlem için önce araca bağlanın.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if ownerTransferRequired {
                    Text("Araç eski telefon anahtarına bağlı. Sahip anahtarını bu iPhone'a taşımak, eski telefonun dijital anahtarını geçersiz kılar.")
                        .font(.caption).foregroundStyle(.orange)
                    Button(role: .destructive) {
                        Task { await authenticate(overwriteOwner: true) }
                    } label: {
                        Label("Sahip anahtarını iPhone'a taşı", systemImage: "arrow.right.circle")
                    }
                    .disabled(busy)
                }
            }

            if let telemetry = ble.telemetry {
                Section("Araç durumu (Bluetooth)") {
                    HStack { Text("Kilit"); Spacer(); Text(telemetry.lockText) }
                    if telemetry.hasDoorReadings {
                        ForEach(0..<4, id: \.self) { index in
                            HStack {
                                Text("Kapı \(index + 1)")
                                Spacer()
                                Text(telemetry.isDoorOpen(index) == true ? "Açık" : "Kapalı")
                            }
                        }
                    } else {
                        HStack { Text("Kapılar"); Spacer(); Text("Durum doğrulanıyor") }
                    }
                    HStack { Text("Bagaj"); Spacer(); Text(telemetry.trunkAjar == 1 ? "Açık" : "Kapalı") }
                    HStack { Text("Güç durumu"); Spacer(); Text(telemetry.powerStateText) }
                    Text("Güncelleme: \(telemetry.receivedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Kapı 1–4, telemetrideki door1–door4 alanlarıdır; fiziksel kapı konumları henüz doğrulanmadı.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Section("Komutlar") {
                Button("Kilidi aç") { pending = .unlock }.disabled(!commandsEnabled)
                Button("Kilitle") { pending = .lock }.disabled(!commandsEnabled)
                Button("Bagajı aç") { pending = .trunkOpen }.disabled(!commandsEnabled)
                Button("Bagajı kapat") { pending = .trunkClose }.disabled(!commandsEnabled)
                Button("Sürüş yetkilendir") { pending = .driveAuthorize }
                    .disabled(!commandsEnabled)
                    .buttonStyle(.borderedProminent)
                if !ble.state.isReady {
                    Text("Komutlar, araç kimliği doğrulandıktan sonra etkinleşir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Tanı kaydını temizle", role: .destructive) {
                    ble.clearDiagnosticEvents()
                }
                ForEach(Array(ble.diagnosticEvents.suffix(80).reversed())) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.message)
                            .font(.caption)
                            .textSelection(.enabled)
                        Text(event.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("BLE tanı günlüğü · son \(ble.diagnosticEvents.count)")
            } footer: {
                Text("Son 200 olay bu iPhone’da tutulur; erişim anahtarı ve ham imza kaydedilmez.")
            }

            Section("Uyarı") {
                Text("Komutlar gerçek araca gönderilir. Yalnızca aracın yanındayken ve gerektiğinde kullanın.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let error {
                Section("Hata") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            if !message.isEmpty {
                Section("Son olay") { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Araç komutları")
        .onReceive(ble.$lastEvent) { message = $0 }
        .alert("Komut gönderilsin mi?", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        ), presenting: pending) { command in
            Button("Gönder", role: .destructive) { send(command) }
            Button("Vazgeç", role: .cancel) { }
        } message: { command in
            Text(command.detail)
        }
    }

    private func authenticate(overwriteOwner: Bool = false) async {
        busy = true
        error = nil
        ownerTransferRequired = false
        defer { busy = false }
        do {
            try await ble.authenticate(vehicle: vehicle, api: api, overwriteOwner: overwriteOwner)
        } catch CertificateServiceError.ownerTransferRequired {
            ownerTransferRequired = true
            self.error = CertificateServiceError.ownerTransferRequired.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send(_ command: PendingCommand) {
        switch command {
        case .unlock: ble.unlock()
        case .lock: ble.lock()
        case .trunkOpen: ble.trunkOpen()
        case .trunkClose: ble.trunkClose()
        case .driveAuthorize: ble.driveAuthorize()
        }
    }
}
