import CoreBluetooth
import Foundation

public final class BLEInputSource: NSObject, @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case off
        case unauthorized
        case poweredOff
        case scanning
        case connecting(String)
        case probing(String)
        case connected(String)
    }

    public static let compactInputCharacteristicUUID = "7492866c-ec3e-4619-8258-32755ffcc0f9"
    static var compactInputCharacteristic: CBUUID { CBUUID(string: compactInputCharacteristicUUID) }
    public static let nintendoCompanyIDs: Set<UInt16> = [0x0553, 0x057E]
    static let reconnectWindow: TimeInterval = 60
    static let probeTimeout: TimeInterval = 3

    public typealias StateHandler = @Sendable (ControllerState) -> Void
    public typealias StatusHandler = @Sendable (Status) -> Void

    private let queue = DispatchQueue(label: "com.p1rate.ns2controller.ble")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var inputCharacteristic: CBCharacteristic?
    private var candidates: [CBCharacteristic] = []
    private var pendingServices = 0
    private var stopped = true
    private let onState: StateHandler
    private let onStatus: StatusHandler
    public private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatus(status) } }
    }
    public var onRawReport: (@Sendable ([UInt8]) -> Void)?

    public init(onStatus: @escaping StatusHandler, onState: @escaping StateHandler) {
        self.onStatus = onStatus
        self.onState = onState
        super.init()
    }

    public func start() {
        queue.async { [self] in
            stopped = false
            if central == nil {
                central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
            } else {
                beginScan()
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            central?.stopScan()
            if let peripheral { central?.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            inputCharacteristic = nil
            candidates.removeAll()
            status = .off
        }
    }

    private func beginScan() {
        guard let central, !stopped, central.state == .poweredOn else { return }
        Log.info("BLE: scanning for Switch 2 controllers (hold the sync button on the controller)")
        status = .scanning
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    static func isSwitch2Advertisement(name: String?, manufacturerData: Data?) -> Bool {
        if let data = manufacturerData, data.count >= 2 {
            let company = UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
            if nintendoCompanyIDs.contains(company) { return true }
        }
        if let name, name.localizedCaseInsensitiveContains("Pro Controller") || name.localizedCaseInsensitiveContains("Joy-Con") {
            return true
        }
        return false
    }

    private func handle(report data: Data, from characteristic: CBCharacteristic) {
        let bytes = [UInt8](data)
        if inputCharacteristic == nil {
            guard bytes.count >= 11 else { return }
            inputCharacteristic = characteristic
            for other in candidates where other != characteristic { peripheral?.setNotifyValue(false, for: other) }
            candidates.removeAll()
            Log.info("BLE: input characteristic \(characteristic.uuid.uuidString) (\(bytes.count) bytes)")
            status = .connected(peripheral?.name ?? "Switch 2 controller")
        }
        guard characteristic == inputCharacteristic else { return }
        onRawReport?(bytes)
        if let state = InputReport.parseCompactBLE(bytes) { onState(state) }
    }
}

extension BLEInputSource: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScan()
        case .unauthorized:
            Log.error("BLE: Bluetooth access denied for this app (System Settings → Privacy & Security → Bluetooth)")
            status = .unauthorized
        case .poweredOff:
            Log.warn("BLE: Bluetooth is off")
            status = .poweredOff
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        guard Self.isSwitch2Advertisement(name: name, manufacturerData: manufacturer) else { return }
        Log.info("BLE: found \(name ?? "controller") rssi=\(RSSI) manufacturer=\(manufacturer.map { [UInt8]($0).hexString } ?? "-")")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        status = .connecting(name ?? "controller")
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Log.info("BLE: connected to \(peripheral.name ?? "controller"), discovering services")
        inputCharacteristic = nil
        candidates.removeAll()
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Log.warn("BLE: connection failed: \(error?.localizedDescription ?? "unknown")")
        self.peripheral = nil
        beginScan()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Log.info("BLE: disconnected\(error.map { " (\($0.localizedDescription))" } ?? "")")
        self.peripheral = nil
        inputCharacteristic = nil
        candidates.removeAll()
        guard !stopped else { return }
        beginScan()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, error == nil else {
            Log.warn("BLE: service discovery failed: \(error?.localizedDescription ?? "no services")")
            return
        }
        pendingServices = services.count
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        pendingServices -= 1
        for characteristic in service.characteristics ?? [] {
            Log.debug("BLE: \(service.uuid.uuidString) / \(characteristic.uuid.uuidString) props=\(characteristic.properties.rawValue)")
            if characteristic.uuid == Self.compactInputCharacteristic {
                inputCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                status = .connected(peripheral.name ?? "Switch 2 controller")
                Log.info("BLE: subscribed to compact input characteristic")
                return
            }
            if characteristic.properties.contains(.notify) { candidates.append(characteristic) }
        }
        guard pendingServices == 0, inputCharacteristic == nil else { return }
        guard !candidates.isEmpty else {
            Log.warn("BLE: no notifiable characteristics found")
            return
        }
        Log.info("BLE: compact characteristic not found, probing \(candidates.count) notifiable characteristics")
        status = .probing(peripheral.name ?? "controller")
        let sorted = candidates.sorted { $0.uuid.uuidString.count > $1.uuid.uuidString.count }
        candidates = sorted
        for characteristic in sorted.prefix(8) { peripheral.setNotifyValue(true, for: characteristic) }
        inputCharacteristic = nil
        queue.asyncAfter(deadline: .now() + Self.probeTimeout) { [self] in
            if inputCharacteristic == nil { Log.warn("BLE: no input reports received from any characteristic") }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { Log.warn("BLE: notify \(characteristic.uuid.uuidString): \(error.localizedDescription)") }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        handle(report: data, from: characteristic)
    }
}
