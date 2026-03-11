import CoreBluetooth
import Foundation

/// Bluetooth LE Heart Rate Monitor — connects to any BLE HR strap (Wahoo, Polar, etc.)
/// Uses the standard Heart Rate Service (0x180D) and Heart Rate Measurement Characteristic (0x2A37).
final class BLEHeartRateMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    static let heartRateServiceUUID = CBUUID(string: "180D")
    static let heartRateMeasurementUUID = CBUUID(string: "2A37")
    static let deviceNameCharacteristicUUID = CBUUID(string: "2A00")

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

    var onHeartRate: ((Int) -> Void)?
    var onStatusChange: ((String) -> Void)?
    var onDeviceFound: ((String) -> Void)?

    private(set) var isConnected = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            onStatusChange?("[BLE] Waiting for Bluetooth to power on...")
            return
        }
        onStatusChange?("[BLE] Scanning for heart rate monitors...")
        centralManager.scanForPeripherals(
            withServices: [Self.heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stop() {
        centralManager.stopScan()
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        isConnected = false
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff:
            onStatusChange?("[BLE] Bluetooth is powered off. Please enable Bluetooth.")
        case .unauthorized:
            onStatusChange?("[BLE] Bluetooth permission denied. Grant access in System Settings > Privacy.")
        case .unsupported:
            onStatusChange?("[BLE] Bluetooth LE not supported on this Mac.")
        default:
            onStatusChange?("[BLE] Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown HR Monitor"
        onDeviceFound?("[BLE] Found: \(name) (RSSI: \(RSSI))")
        onStatusChange?("[BLE] Connecting to \(name)...")

        centralManager.stopScan()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let name = peripheral.name ?? "Unknown"
        onStatusChange?("[BLE] Connected to \(name)")
        isConnected = true
        peripheral.discoverServices([Self.heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onStatusChange?("[BLE] Disconnected. Rescanning...")
        isConnected = false
        connectedPeripheral = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        onStatusChange?("[BLE] Failed to connect: \(error?.localizedDescription ?? "unknown error"). Rescanning...")
        connectedPeripheral = nil
        startScanning()
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == Self.heartRateServiceUUID {
            peripheral.discoverCharacteristics([Self.heartRateMeasurementUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == Self.heartRateMeasurementUUID {
            peripheral.setNotifyValue(true, for: characteristic)
            onStatusChange?("[BLE] Subscribed to heart rate notifications")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.heartRateMeasurementUUID,
              let data = characteristic.value else { return }

        let heartRate = parseHeartRate(data: data)
        onHeartRate?(heartRate)
    }

    // MARK: - Parsing

    /// Parse the Heart Rate Measurement characteristic per Bluetooth SIG spec.
    /// Bit 0 of flags: 0 = UInt8 HR value, 1 = UInt16 HR value.
    private func parseHeartRate(data: Data) -> Int {
        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0

        if is16Bit && data.count >= 3 {
            return Int(UInt16(data[1]) | (UInt16(data[2]) << 8))
        } else if data.count >= 2 {
            return Int(data[1])
        }
        return 0
    }
}
