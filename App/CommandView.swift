import SwiftUI

struct CommandView: View {
    let vehicle: Vehicle
    let api: ToggAPI
    /// Bağlantı koordinatörünün son durumu. Otomatik kimlik doğrulama
    /// reddedildiğinde nedeni burada görünür; komutlar sessizce kapanmaz.
    var linkStatus: String = ""

    @EnvironmentObject private var ble: BleConnection
    @State private var message = ""
    @State private var error: String?
    @State private var busy = false
    @State private var pending: PendingCommand?
    @State private var showChannels = false
    @State private var ownerTransferRequired = false
    @State private var shareVIN = ""
    @State private var shareInvitationURL = ""
    @State private var shareBusy = false
    @State private var shareStatus = ""
    @State private var shareError: String?
    @State private var showShareConfirmation = false
    /// Rapor yalnızca tanı olayları değiştiğinde yeniden hesaplanır. Daha önce
    /// her `body` değerlendirmesinde 15 kez hesaplanıyordu; BLE olayları
    /// sıklaştığında ana iş parçacığını doldurup uygulamayı sonlandırabiliyordu.
    @State private var diagnosticReport = BLEDiagnosticReport(events: [])

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
    private var commandsEnabled: Bool { ble.canSendVehicleCommands && !busy }
    private var ownerTransferSuggested: Bool {
        ownerTransferRequired
            || linkStatus.contains("Sahip anahtarını")
            || linkStatus.contains("başka bir telefon anahtarına bağlı")
    }

    var body: some View {
        List {
            Section("Araç") {
                Text(vehicle.title)
                Text(vehicle.vin).font(.caption).monospaced()
            }

            Section("Bluetooth") {
                Text(ble.state.description)
                if !linkStatus.isEmpty, !ble.state.isReady, linkStatus != ble.state.description {
                    Text(linkStatus)
                        .font(.caption)
                        .foregroundStyle(linkStatus.contains("başarısız") ? .orange : .secondary)
                }
                if let receipt = ble.lastCommandReceipt {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Son komut: \(receipt.summary)")
                            .font(.footnote)
                            .foregroundStyle(receipt.phase.isFailure ? .orange : .secondary)
                        if let detail = receipt.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if ble.pairingRequired, !ble.state.isReady {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Araç eşleştirmesi gerekiyor", systemImage: "key.fill")
                            .font(.footnote.bold()).foregroundStyle(.orange)
                        Text("1. Araç ekranında dijital anahtar / telefon eşleştirme bölümünü aç.\n2. Bu iPhone’u seç ve eşleştirmeyi başlat.\n3. Araçta onay kodu görünürse iPhone’daki kodla karşılaştır.\n4. Bu ekranda bağlantıyı açık tut; araç doğrulama anahtarı gelince oturum READY olur.")
                            .font(.caption)
                        Text("Sertifika araca sunuldu ancak araç doğrulama anahtarı henüz gelmedi.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
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

            if !ble.commandHistory.isEmpty {
                Section {
                    ForEach(ble.commandHistory.prefix(10)) { receipt in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(receipt.summary)
                                .font(.footnote)
                                .foregroundStyle(receipt.phase.isFailure ? .orange : .primary)
                            if let detail = receipt.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(receipt.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    Button("Komut geçmişini temizle", role: .destructive) {
                        ble.clearCommandHistory()
                    }
                } header: {
                    Text("Son komutlar")
                } footer: {
                    Text("Son 20 komut bu iPhone’da saklanır; anahtar, imza ve ham paket kaydedilmez.")
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
                if ownerTransferSuggested {
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

            Section("Paylaşılan anahtar daveti") {
                Text("Trumore'dan aldığın KeySharing bağlantısını ve davetteki VIN'i gir. Bu işlem sahiplik devretmez; araç sahibinin Trumore onayı gerekir.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("VIN (17 karakter)", text: $shareVIN)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced())
                    .onChange(of: shareVIN) { shareVIN = String($0.uppercased().filter { $0.isASCII }.prefix(17)) }
                TextField("https://…/KeySharing?seId=…&no=…", text: $shareInvitationURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption)

                Button {
                    showShareConfirmation = true
                } label: {
                    Label(shareBusy ? "Davet gönderiliyor…" : "İmzalı davet kabul isteği gönder",
                          systemImage: "person.2.badge.key.fill")
                }
                .disabled(shareBusy || !isValidShareVIN || shareInvitationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await readSharedCertificate() }
                } label: {
                    Label(shareBusy ? "Sertifika sorgulanıyor…" : "Onay sonrası sertifikayı oku",
                          systemImage: "arrow.down.document.fill")
                }
                .disabled(shareBusy || !isValidShareVIN)

                if !shareStatus.isEmpty {
                    Text(shareStatus).font(.caption).foregroundStyle(.secondary)
                }
                if let shareError {
                    Text(shareError).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }

                Button(role: .destructive) {
                    SharedKeyRequestStore.clearSharingState(vin: shareVIN)
                    shareStatus = "Paylaşım durumu sıfırlandı. Araç sahibi akışına dönüldü."
                    shareError = nil
                } label: {
                    Label("Paylaşım durumunu sıfırla", systemImage: "trash")
                }
                .font(.caption)
            }

            Section("Komutlar") {
                Button("Kilidi aç") { pending = .unlock }.disabled(!commandsEnabled)
                Button("Kilitle") { pending = .lock }.disabled(!commandsEnabled)
                Button("Bagajı aç") { pending = .trunkOpen }.disabled(!commandsEnabled)
                Button("Bagajı kapat") { pending = .trunkClose }.disabled(!commandsEnabled)
                Button("Sürüş yetkilendir") { pending = .driveAuthorize }
                    .disabled(!commandsEnabled)
                    .buttonStyle(.borderedProminent)
                if !ble.canSendVehicleCommands {
                    Text(commandGateMessage)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                diagnosticMetric("Tarama / devir / sonuçsuz", "\(diagnosticReport.scanStarts) / \(diagnosticReport.scanRotations) / \(diagnosticReport.scanExhaustions)")
                diagnosticMetric("Bağlandı / koptu / READY", "\(diagnosticReport.successfulConnections) / \(diagnosticReport.disconnects) / \(diagnosticReport.readyTransitions)")
                diagnosticMetric("Doğrudan yeniden bağlanma", "\(diagnosticReport.directReconnects)")
                diagnosticMetric("Radyo aç / kapat", "\(diagnosticReport.radioOnEvents) / \(diagnosticReport.radioOffEvents)")
                diagnosticMetric("RSSI örnekleri", "\(diagnosticReport.rssiSamples.count) · \(diagnosticReport.rssiSummary)")
                diagnosticMetric("Eksik araç anahtarı", "\(diagnosticReport.missingVehicleKeys)")
                diagnosticMetric("Telemetri doğrulama hatası", "\(diagnosticReport.telemetryVerificationFailures)")
                diagnosticMetric("Eski GATT RSSI / yakınlık döngüsü sıfırlama", "\(diagnosticReport.staleGATTRSSISamples) / \(diagnosticReport.proximityFreshCycleResets)")

                if diagnosticReport.totalFailures == 0 {
                    Text("Son 60 dakikada sınıflandırılmış kopma/hata yok.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(BleFailureKind.allCases, id: \.rawValue) { kind in
                        if let count = diagnosticReport.failureCounts[kind], count > 0 {
                            diagnosticMetric(kind.summary, "\(count)")
                        }
                    }
                }

                ShareLink(item: diagnosticReport.shareText) {
                    Label("Tanı özetini paylaş", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("BLE tanı özeti · son 60 dk")
            } footer: {
                Text("Özet son bir saatteki, bu iPhone’da tutulan en fazla 500 olaydan hesaplanır. VIN redakte edilir; anahtarlar ve ham paketler rapora eklenmez.")
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
                Text("Son 500 olay bu iPhone’da tutulur; erişim anahtarı ve ham imza kaydedilmez.")
            }

            Section("Uyarı") {
                Text("Komutlar gerçek araca gönderilir. Yalnızca aracın yanındayken ve gerektiğinde kullanın.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            #if DEBUG
            Section("Ses testi · yalnızca ses") {
                Button {
                    LockConfirmationSound.playDoubleBeep()
                } label: {
                    Label("Kilit teyit sesini dene", systemImage: "speaker.wave.2.fill")
                }
                Text("Bu düğme araca komut göndermez.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif

            if let error {
                Section("Hata") { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            if !message.isEmpty {
                Section("Son olay") { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Araç komutları")
        .onReceive(ble.$lastEvent) { message = $0 }
        .onReceive(ble.$diagnosticEvents) { events in
            diagnosticReport = BLEDiagnosticReport(events: events)
        }
        .alert("Komut gönderilsin mi?", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        ), presenting: pending) { command in
            Button("Gönder", role: .destructive) { send(command) }
            Button("Vazgeç", role: .cancel) { }
        } message: { command in
            Text(command.detail)
        }
        .confirmationDialog("Paylaşılan anahtar daveti kabul edilsin mi?",
                            isPresented: $showShareConfirmation,
                            titleVisibility: .visible) {
            Button("İmzalı kabul isteği gönder", role: .destructive) {
                Task { await acceptSharedInvitation() }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Yalnızca bu VIN için telefon açık anahtarı ve davet imzası gönderilir. Araç sahipliği değişmez; Trumore araç sahibinin onayı beklenir. Aynı davet otomatik tekrarlanmaz.")
        }
        .onAppear {
            diagnosticReport = BLEDiagnosticReport(events: ble.diagnosticEvents)
            if shareVIN.isEmpty { shareVIN = vehicle.vin }
        }
    }

    private var isValidShareVIN: Bool {
        shareVIN.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil
    }

    @MainActor
    private func acceptSharedInvitation() async {
        guard !shareBusy else { return }
        shareBusy = true
        shareError = nil
        shareStatus = ""
        defer { shareBusy = false }
        do {
            try await api.acceptSharedKeyInvitation(vin: shareVIN, invitationURL: shareInvitationURL)
            shareInvitationURL = ""
            shareStatus = "Kabul isteği imzalanıp gönderildi. Araç sahibinin Trumore onayından sonra sertifikayı oku."
        } catch {
            shareError = error.localizedDescription
        }
    }

    @MainActor
    private func readSharedCertificate() async {
        guard !shareBusy else { return }
        shareBusy = true
        shareError = nil
        shareStatus = ""
        defer { shareBusy = false }
        do {
            let record = try await api.readSharedCertificate(vin: shareVIN)
            shareStatus = record.carPublicKey.isEmpty
                ? "Paylaşılan sertifika alındı; araç doğrulama anahtarı henüz yok. READY için araç anahtarı gerekli."
                : "Paylaşılan sertifika ve araç anahtarı Keychain'e kaydedildi. Araç yanında bağlanıp doğrula."
            if shareVIN == vehicle.vin, (ble.state.isCertificate || ble.state.isChallenge) {
                try ble.beginAuthentication(
                    vin: shareVIN,
                    certificateBase64: record.certificateBase64,
                    carKey: record.carPublicKey
                )
            }
        } catch {
            shareError = error.localizedDescription
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

    private func diagnosticMetric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
        }
    }

    private var commandGateMessage: String {
        if !ble.state.isReady, !linkStatus.isEmpty { return linkStatus }
        guard ble.state.isReady else { return "Komutlar, araç kimliği doğrulandıktan sonra etkinleşir." }
        guard ble.hasFreshSignedTelemetry else { return "Komut için 15 saniyeden yeni imzalı araç durumu gerekli." }
        return "Kilit durumu bilinmiyor; araç komutları güvenlik için kapalı."
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
