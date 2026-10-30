import CoreBluetooth
import XCTest
@testable import ToqdasCore

private final class FakeBLETransport: BLETransporting {
    weak var delegate: BLETransportDelegate?
    var state: CBManagerState
    var isRadioOn: Bool { state == .poweredOn }

    private(set) var scanOptions: [Bool] = []
    private(set) var stopScanCount = 0

    init(state: CBManagerState) {
        self.state = state
    }

    func startScan(allowDuplicates: Bool) {
        scanOptions.append(allowDuplicates)
    }

    func stopScan() {
        stopScanCount += 1
    }

    func connect(_ peripheral: CBPeripheral) {}

    func disconnect() {}

    func stop() {
        stopScan()
    }

    func emit(_ state: CBManagerState) {
        self.state = state
        delegate?.transportDidUpdateState(state)
    }
}

@MainActor
final class BLETransportTests: XCTestCase {
    private let vin = "NL1CSU0P60G064536"

    func testRadioOffRejectsStartWithoutScanning() {
        let transport = FakeBLETransport(state: .poweredOff)
        let ble = BleConnection(transport: transport)

        ble.start(vin: vin)

        XCTAssertTrue(ble.state.isFailed)
        XCTAssertTrue(transport.scanOptions.isEmpty)
    }

    func testRadioOnStartsFirstScanPhase() {
        let transport = FakeBLETransport(state: .poweredOn)
        let ble = BleConnection(transport: transport)

        ble.start(vin: vin)
        defer { ble.stop() }

        XCTAssertEqual(transport.scanOptions.count, 1)
        XCTAssertTrue(ble.state.isConnecting)
    }

    func testRadioOffStopsScanAndMarksFailure() {
        let transport = FakeBLETransport(state: .poweredOn)
        let ble = BleConnection(transport: transport)
        ble.start(vin: vin)

        transport.emit(.poweredOff)

        XCTAssertTrue(ble.state.isFailed)
        XCTAssertGreaterThanOrEqual(transport.stopScanCount, 1)
    }

    func testManualStopResetsSession() {
        let transport = FakeBLETransport(state: .poweredOn)
        let ble = BleConnection(transport: transport)
        ble.start(vin: vin)

        ble.stop()

        XCTAssertTrue(ble.state.isDisconnected)
        XCTAssertGreaterThanOrEqual(transport.stopScanCount, 1)
    }
}
