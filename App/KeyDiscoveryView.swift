import CoreBluetooth
import SwiftUI

/// Tanıtma (keyDiscovery) aday seçim taramacısı.
///
/// Neden ayrı sınıf: `BleConnection`'ın kendi otomatik bağlantı akışı
/// var (ilk eşleşen çevrebirime bağlanır). Aday seçim akışı bilinçli
/// olarak **bağlanmaz**: yalnız gözlem toplar, kullanıcı seçer, bağlantı
/// kararını kullanıcı verir. Ayrı `CBCentralManager` örneği bu ayrımı
/// taşımalarla bozmadan sağlar.
///
/// Parite (Android `Q4`): tarama penceresi 12 sn; hiçbir araç komutu
/// gönderilmez; kanıtsız cihazlar "Elendi" metniyle görünmez yerine
/// yalnız geçerli adaylar listelenir.
final class KeyDiscoveryScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    /// Araç servisinin BLE servis UUID'si (`BleConnection` ile aynı).
    private let serviceUUID = CBUUID(string: "f0002412-0451-4000-b000-000000000000")

    @Published private(set) var session: KeyDiscoverySession
    @Published private(set) var isScanning = false
    @Published private(set) var isRadioOn = false
    @Published private(set) var lastMessage = "Cihazları Tara düğmesine basın."

    /// Görülen çevrebirimler: oturum anahtarı (peripheral.identifier)
    /// → örnek. "Bağlan" bu örneklerle yapılır.
    private(set) var discovered: [String: CBPeripheral] = [:]

    /// Son bağlanılan çevrebirim tanımı ("kayıtlı adres" kanıtı).
    var knownPeripheralIdentifier: UUID?

    private var central: CBCentralManager?
    private var scanDeadlineTask: Task<Void, Never>?
    /// Tarama penceresi: sabit `KeyDiscoveryPolicy.scanWindow` (12 sn).

    init(vin: String) {
        session = KeyDiscoverySession(vin: vin)
        super.init()
    }

    func peripheral(for identifier: String) -> CBPeripheral? {
        discovered[identifier]
    }

    func activate() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    /// 12 sn'lik tek tarama penceresi; tekrar basılırsa yeniden başlar.
    func scan() {
        guard let central, central.state == .poweredOn else {
            lastMessage = "Bluetooth kapalı veya hazırlanıyor; radyoyu açın."
            return
        }
        guard !isScanning else { return }
        scanDeadlineTask?.cancel()
        session.beginScan()
        isScanning = true
        lastMessage = "Tanıtma taraması etkin · en çok 12sn · hiçbir araç komutu gönderilmez."
        // Android birebir: servis filtresiz tarama; kanıt reklamdan okunur.
        central.scanForPeripherals(withServices: nil, options: nil)
        scanDeadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(KeyDiscoveryPolicy.scanWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finishScan()
        }
    }

    private func finishScan() {
        central?.stopScan()
        session.endScan()
        isScanning = false
        let valid = session.sortedValidCandidates.count
        lastMessage = valid == 0
            ? "Geçerli aday bulunamadı. Araca yakınken tekrar deneyin."
            : "Tarama bitti; \(valid) geçerli aday. Seçin ve bağlanın."
    }

    func stop() {
        scanDeadlineTask?.cancel()
        scanDeadlineTask = nil
        if isScanning {
            central?.stopScan()
            session.endScan()
            isScanning = false
        }
    }

    /// Seçilen adayı doğrular; bağlanılabilir çevrebirimi döner.
    /// Araç komutu göndermez — bağlantı çağıran taraftadır.
    func selectAndPrepare(_ identifier: String) -> CBPeripheral? {
        guard let candidate = session.select(identifier) else {
            lastMessage = KeyDiscoveryPolicy.selectionStaleMessage
            return nil
        }
        guard let peripheral = discovered[identifier] else {
            lastMessage = "Aday çevrebirimi artık görünmüyor; tekrar tarayın."
            return nil
        }
        lastMessage = "Aday seçildi: \(candidate.name ?? "isimsiz"). Bağlanmak için onaylayın."
        return peripheral
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isRadioOn = central.state == .poweredOn
        if central.state != .poweredOn, isScanning {
            session.failScan("Bluetooth radyosu kapanandı; tarama durduruldu.")
            isScanning = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertisedName
        let advertisedUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let identifier = peripheral.identifier.uuidString
        discovered[identifier] = peripheral
        session.observe(
            identifier: identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisesSupportedService: advertisedUUIDs.contains(serviceUUID),
            matchesRegisteredAddress: peripheral.identifier == knownPeripheralIdentifier
        )
    }
}

/// Tanıtma aday seçim ekranı: Tara → geçerli aday listesi → Seç →
/// Bağlan. "Bağlan" mevcut `BleConnection` el sıkışma/anahtar öğrenme
/// akışını başlatır (yeni kod yazılmaz); ekranın kendisi araç komutu
/// göndermez.
struct KeyDiscoveryView: View {
    @EnvironmentObject private var ble: BleConnection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner: KeyDiscoveryScanner
    @State private var selectedID: String?
    @State private var connecting = false

    private let vin: String

    init(ble: BleConnection, vin: String) {
        self.vin = vin
        _scanner = StateObject(wrappedValue: KeyDiscoveryScanner(vin: vin))
        // knownPeripheralIdentifier başlangıçta atanamaz (@StateObject
        // init'te bir kez kurulur); .onAppear'da senkronlanır.
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Çoklu cihaz ortamında doğru aracı seçmek için 12 saniyelik bir tarama yapılır. Aday seçimi hiçbir araç komutu göndermez; bağlantıyı ayrıca onaylarsın.")
                        .font(.footnote)
                        .foregroundStyle(ToggTheme.muted)

                    Button { scanner.scan() } label: {
                        HStack {
                            if scanner.isScanning {
                                ProgressView().tint(.white).scaleEffect(0.8)
                                Text("Taranıyor… (12 sn)")
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Cihazları Tara")
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(scanner.isScanning ? ToggTheme.muted : ToggTheme.teal))
                    }
                    .buttonStyle(.plain)
                    .disabled(scanner.isScanning || !scanner.isRadioOn)

                    if !scanner.isRadioOn {
                        Label("Bluetooth kapalı veya hazırlanıyor.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(ToggTheme.orange)
                    }

                    Text(scanner.lastMessage)
                        .font(.caption).foregroundStyle(ToggTheme.muted)

                    let candidates = scanner.session.sortedValidCandidates
                    if candidates.isEmpty {
                        Text("Geçerli aday yok. Ad eşleşmesi için aracın yakınında ol; T-SAS servisi yayınlayan cihazlar da aday olarak sayılır.")
                            .font(.caption).foregroundStyle(ToggTheme.muted)
                    } else {
                        ForEach(candidates, id: \.id) { candidate in
                            candidateRow(candidate)
                        }
                    }

                    Text("Durum: \(scanner.session.statusCode()) · görülen \(scanner.session.rawSightingCount) çevrebirim")
                        .font(.caption2).foregroundStyle(ToggTheme.muted)
                }
                .padding(16)
            }
            .navigationTitle("Aday Seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        scanner.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            scanner.knownPeripheralIdentifier = ble.lastConnectedPeripheralIdentifier
            scanner.activate()
        }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: KeyDiscoveryCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name ?? "İsimsiz cihaz")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    Text(candidate.reason)
                        .font(.caption2).foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let rssi = candidate.rssi {
                    Text("\(rssi) dBm")
                        .font(.caption).foregroundStyle(ToggTheme.teal)
                } else {
                    Text("— dBm")
                        .font(.caption).foregroundStyle(ToggTheme.muted)
                }
            }
            if selectedID == candidate.id {
                Button {
                    connectSelected(candidate.id)
                } label: {
                    HStack {
                        if connecting { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text("Bağlan ve anahtar öğren")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.green))
                }
                .buttonStyle(.plain)
                .disabled(connecting)
            } else {
                Button {
                    selectedID = candidate.id
                } label: {
                    Text("Seç")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ToggTheme.teal)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(scanner.isScanning)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant.opacity(0.6)))
    }

    private func connectSelected(_ identifier: String) {
        connecting = true
        guard let peripheral = scanner.selectAndPrepare(identifier) else {
            connecting = false
            return
        }
        // Mevcut el sıkışma/anahtar öğrenme akışı başlar; ekran kapanır.
        scanner.stop()
        ble.connect(to: peripheral)
        connecting = false
        dismiss()
    }
}
