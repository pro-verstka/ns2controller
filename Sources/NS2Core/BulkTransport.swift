import Foundation
import IOKit
import IOUSBHost

public final class BulkTransport {
    private static let bulkEndpointType: UInt8 = 2
    private static let endpointDirectionIn: UInt8 = 1

    public let info: USBDeviceInfo
    public let inAddress: UInt8
    public let outAddress: UInt8
    public let inMaxPacketSize: Int
    private let interface: IOUSBHostInterface
    private let inPipe: IOUSBHostPipe
    private let outPipe: IOUSBHostPipe
    private var destroyed = false

    public convenience init() throws {
        guard let info = IORegistry.findBulkInterfaces().first else { throw NS2Error.deviceNotFound }
        defer { IOObjectRelease(info.service) }
        try self.init(service: info.service)
    }

    public init(service: io_service_t) throws {
        guard let info = IORegistry.deviceInfo(service) else { throw NS2Error.deviceNotFound }
        self.info = info
        do {
            interface = try IOUSBHostInterface(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw NS2Error.usb("open USB interface \(USBIDs.bulkInterfaceNumber) of \(info.description)", error)
        }
        let config = interface.configurationDescriptor
        let descriptor = interface.interfaceDescriptor
        var inAddress: UInt8?
        var outAddress: UInt8?
        var inMaxPacket = 64
        var cursor: UnsafePointer<IOUSBDescriptorHeader>? = nil
        while let endpoint = IOUSBGetNextEndpointDescriptor(config, descriptor, cursor) {
            cursor = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
            guard IOUSBGetEndpointType(endpoint) == Self.bulkEndpointType else { continue }
            let address = IOUSBGetEndpointAddress(endpoint)
            if IOUSBGetEndpointDirection(endpoint) == Self.endpointDirectionIn {
                inAddress = address
                inMaxPacket = Int(endpoint.pointee.wMaxPacketSize)
            } else {
                outAddress = address
            }
        }
        guard let inAddress, let outAddress else {
            interface.destroy()
            throw NS2Error.endpointsNotFound
        }
        self.inAddress = inAddress
        self.outAddress = outAddress
        self.inMaxPacketSize = max(8, inMaxPacket)
        do {
            inPipe = try interface.copyPipe(withAddress: Int(inAddress))
            outPipe = try interface.copyPipe(withAddress: Int(outAddress))
        } catch {
            interface.destroy()
            throw NS2Error.usb("copy bulk pipes", error)
        }
        Log.debug(String(format: "opened %@: bulk OUT 0x%02x, IN 0x%02x (max packet %d)",
                         info.description, outAddress, inAddress, inMaxPacketSize))
    }

    deinit {
        close()
    }

    public func close() {
        guard !destroyed else { return }
        destroyed = true
        interface.destroy()
    }

    @discardableResult
    public func send(_ bytes: [UInt8], timeout: TimeInterval = 1.0) throws -> Int {
        let data = NSMutableData(bytes: bytes, length: bytes.count)
        var transferred = 0
        do {
            try outPipe.__sendIORequest(with: data, bytesTransferred: &transferred, completionTimeout: timeout)
        } catch {
            throw NS2Error.usb("bulk OUT \(bytes.count) bytes", error)
        }
        return transferred
    }

    public func receive(maxLength: Int = 64, timeout: TimeInterval = 0.1) throws -> [UInt8] {
        var result: [UInt8] = []
        var remaining = maxLength
        while remaining > 0 {
            let chunk = min(remaining, inMaxPacketSize)
            guard let data = NSMutableData(length: chunk) else { break }
            var transferred = 0
            do {
                try inPipe.__sendIORequest(with: data, bytesTransferred: &transferred, completionTimeout: timeout)
            } catch let error as NSError {
                if Self.isTimeout(error) { break }
                throw NS2Error.usb("bulk IN", error)
            }
            result.append(contentsOf: UnsafeBufferPointer(start: data.mutableBytes.assumingMemoryBound(to: UInt8.self), count: transferred))
            remaining -= transferred
            if transferred < chunk { break }
        }
        return result
    }

    private static func isTimeout(_ error: NSError) -> Bool {
        UInt32(bitPattern: Int32(truncatingIfNeeded: error.code)) == 0xE00002D6
    }
}
