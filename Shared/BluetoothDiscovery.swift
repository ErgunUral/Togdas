import CoreBluetooth
import Combine

// Diagnostic transport only. Service discovery does not authenticate a vehicle.
final class BluetoothDiscovery: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Device: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
    }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var status = "Tarama başlatılmadı"
    @Published private(set) var scanning = false
    @Published private(set) var activeDeviceID: UUID?
    @Published private(set) var channels: [String] = []
    @Published private(set) var connectionRSSI: Int?
    @Published private(set) var discoveryComplete = false
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var connectionTimeout: Timer?
    private var pendingServices = Set<CBUUID>()
    private var central: CBCentralManager?
    private var requested = false
    private var timeout: Timer?
    static let service = CBUUID(string: "f0002412-0451-4000-b000-000000000000")
    private static let command = CBUUID(string: "f0002413-0451-4000-b000-000000000000")
    private static let telemetry = CBUUID(string: "f0002415-0451-4000-b000-000000000000")
    private static let timeService = CBUUID(string: "1805")
    private static let time = CBUUID(string: "2A2B")

    func start() {
        guard activeDeviceID == nil else { return }
        devices = []
        peripherals = [:]
        channels = []
        requested = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { beginIfReady() }
    }

    func stop() {
        requested = false
        timeout?.invalidate()
        timeout = nil
        central?.stopScan()
        scanning = false
        if activeDeviceID == nil { status = "Tarama durduruldu" }
    }

    func connect(to id: UUID) {
        guard activeDeviceID == nil, central?.state == .poweredOn,
              let peripheral = peripherals[id] else { return }
        stop()
        channels = []
        connectionRSSI = nil
        discoveryComplete = false
        activePeripheral = peripheral
        activeDeviceID = id
        peripheral.delegate = self
        status = "Bluetooth bağlantısı kuruluyor…"
        armTimeout()
        central?.connect(peripheral)
    }

    func disconnect() {
        endConnection("Bağlantı kesildi")
    }

    func shutdown() {
        stop()
        endConnection("Bluetooth işlemi durduruldu")
    }

    private func endConnection(_ message: String) {
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        let peripheral = activePeripheral
        activePeripheral = nil
        activeDeviceID = nil
        pendingServices.removeAll()
        discoveryComplete = false
        connectionRSSI = nil
        channels = []
        peripheral?.delegate = nil
        if let peripheral, peripheral.state != .disconnected { central?.cancelPeripheralConnection(peripheral) }
        status = message
    }

    private func armTimeout() {
        connectionTimeout?.invalidate()
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.endConnection("Bağlantı/servis keşfi zaman aşımına uğradı. Tekrar deneyin.")
        }
    }

    func refreshRSSI() {
        guard discoveryComplete else { return }
        activePeripheral?.readRSSI()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === activePeripheral else { central.cancelPeripheralConnection(peripheral); return }
        status = "Bağlandı; servisler keşfediliyor…"
        armTimeout()
        peripheral.discoverServices([Self.service, Self.timeService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === activePeripheral else { return }
        endConnection("Bluetooth bağlantısı kurulamadı.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === activePeripheral else { return }
        endConnection("Araç bağlantısı kesildi; durum bilinmiyor.")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === activePeripheral else { return }
        guard error == nil, let services = peripheral.services,
              services.contains(where: { $0.uuid == Self.service }) else {
            endConnection("Araç dijital anahtar servisi bulunamadı.")
            return
        }
        let relevant = services.filter { $0.uuid == Self.service || $0.uuid == Self.timeService }
        pendingServices = Set(relevant.map(\.uuid))
        for service in relevant {
            peripheral.discoverCharacteristics(service.uuid == Self.service ? [Self.command, Self.telemetry] : [Self.time], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === activePeripheral, pendingServices.contains(service.uuid) else { return }
        guard error == nil else { endConnection("Bluetooth kanalları keşfedilemedi."); return }
        for characteristic in service.characteristics ?? [] {
            let title: String
            switch characteristic.uuid {
            case Self.command: title = "Komut"
            case Self.telemetry: title = "Telemetri"
            case Self.time: title = "Araç saati"
            default: continue
            }
            var capabilities: [String] = []
            if characteristic.properties.contains(.read) { capabilities.append("okuma") }
            if characteristic.properties.contains(.write) { capabilities.append("yanıtlı yazma") }
            if characteristic.properties.contains(.writeWithoutResponse) { capabilities.append("yanıtsız yazma") }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) { capabilities.append("bildirim") }
            channels.append("\(title): \(capabilities.isEmpty ? "özellik bildirilmedi" : capabilities.joined(separator: ", "))")
        }
        pendingServices.remove(service.uuid)
        guard pendingServices.isEmpty else { return }
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        discoveryComplete = true
        let characteristics = peripheral.services?.first(where: { $0.uuid == Self.service })?.characteristics ?? []
        let complete = [Self.command, Self.telemetry].allSatisfy { uuid in characteristics.contains { $0.uuid == uuid } }
        status = complete ? "Kanallar bulundu • Araç kimliği henüz doğrulanmadı" : "Servis bulundu ancak gerekli kanallar eksik"
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral === activePeripheral else { return }
        connectionRSSI = error == nil && RSSI.intValue != 127 ? RSSI.intValue : nil
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral === activePeripheral else { return }
        endConnection("Bluetooth servisleri değişti; yeniden bağlanın.")
    }

    private func beginIfReady() {
        guard requested, central?.state == .poweredOn else { return }
        scanning = true
        status = "Araç servisi aranıyor (20 saniye)"
        central?.scanForPeripherals(withServices: [Self.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        timeout?.invalidate()
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.stop() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            stop()
            endConnection("Bluetooth hazır değil")
        }
        switch central.state {
        case .poweredOn: status = "Bluetooth hazır"; beginIfReady()
        case .poweredOff: scanning = false; status = "Bluetooth kapalı"
        case .unauthorized: scanning = false; status = "Bluetooth izni gerekiyor"
        case .unsupported: scanning = false; status = "Bluetooth desteklenmiyor"
        default: scanning = false; status = "Bluetooth hazırlanıyor"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning, RSSI.intValue != 127 else { return }
        peripherals[peripheral.identifier] = peripheral
        let device = Device(id: peripheral.identifier,
                            name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Araç servisi",
                            rssi: RSSI.intValue)
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
    }
}
