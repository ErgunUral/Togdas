import CoreBluetooth
import Foundation

/// CoreBluetooth merkezi (central) yaşam döngüsünü BLE oturumundan ayırır.
/// Tarama, bağlanma, kopma ve durum geri yükleme yalnız bu katmanda kalır;
/// el sıkışma ve komut mantığı `BleConnection` içinde devam eder.
protocol BLETransportDelegate: AnyObject {
    func transportDidUpdateState(_ managerState: CBManagerState)
    func transportDidRestore(peripheral: CBPeripheral, count: Int)
    func transportDidDiscover(peripheral: CBPeripheral, name: String, rssi: Int)
    func transportDidConnect(peripheral: CBPeripheral)
    func transportDidFailToConnect(peripheral: CBPeripheral, error: Error?)
    func transportDidDisconnect(peripheral: CBPeripheral, error: Error?)
}

protocol BLETransporting: AnyObject {
    var delegate: BLETransportDelegate? { get set }
    var state: CBManagerState { get }
    var isRadioOn: Bool { get }
    func startScan(allowDuplicates: Bool)
    func stopScan()
    func connect(_ peripheral: CBPeripheral)
    func disconnect()
    func stop()
}

final class BLETransport: NSObject, CBCentralManagerDelegate, BLETransporting {
    weak var delegate: BLETransportDelegate? {
        didSet {
            // CBCentralManager init sırasında durum bildirimi kaybolmasın:
            // delegate bağlanınca bilinen son durum bir kez iletilir.
            let current = state
            if current != .unknown {
                delegate?.transportDidUpdateState(current)
            }
        }
    }

    private var central: CBCentralManager?
    private(set) var peripheral: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.toqdas.ios.central"]
        )
    }

    var state: CBManagerState { central?.state ?? .unknown }
    var isRadioOn: Bool { state == .poweredOn }

    func startScan(allowDuplicates: Bool) {
        guard isRadioOn else { return }
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
    }

    func stopScan() {
        central?.stopScan()
    }

    func connect(_ peripheral: CBPeripheral) {
        guard isRadioOn else { return }
        self.peripheral = peripheral
        central?.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
    }

    func stop() {
        stopScan()
        disconnect()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.transportDidUpdateState(central.state)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = restored.first else { return }
        self.peripheral = peripheral
        delegate?.transportDidRestore(peripheral: peripheral, count: restored.count)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertised ?? "bilinmiyor"
        delegate?.transportDidDiscover(peripheral: peripheral, name: name, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        delegate?.transportDidConnect(peripheral: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        delegate?.transportDidFailToConnect(peripheral: peripheral, error: error)
        if self.peripheral === peripheral {
            self.peripheral = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        delegate?.transportDidDisconnect(peripheral: peripheral, error: error)
        if self.peripheral === peripheral {
            self.peripheral = nil
        }
    }
}
