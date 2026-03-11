import Foundation
import IOKit
import IOKit.usb

/// ANT+ Heart Rate Monitor — communicates with a USB ANT+ stick (e.g., Garmin USB-m)
/// to receive HR data from ANT+ heart rate straps.
///
/// This uses IOKit directly (no libusb dependency) for Apple Silicon compatibility.
/// ANT+ HR profile: device type 0x78 (120), transmission type 0, RF frequency 57 (2457 MHz).
final class ANTHeartRateMonitor {

    // ANT+ constants
    private static let antSyncByte: UInt8 = 0xA4
    private static let antHRDeviceType: UInt8 = 120    // 0x78
    private static let antRFFrequency: UInt8 = 57      // 2457 MHz (ANT+ frequency)
    private static let antChannelPeriod: UInt16 = 8070  // ~4.06 Hz
    private static let antNetworkKey: [UInt8] = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45]

    // ANT message types
    private static let msgSystemReset: UInt8 = 0x4A
    private static let msgSetNetworkKey: UInt8 = 0x46
    private static let msgAssignChannel: UInt8 = 0x42
    private static let msgSetChannelId: UInt8 = 0x51
    private static let msgSetChannelFreq: UInt8 = 0x45
    private static let msgSetChannelPeriod: UInt8 = 0x43
    private static let msgOpenChannel: UInt8 = 0x4B
    private static let msgBroadcastData: UInt8 = 0x4E
    private static let msgChannelResponse: UInt8 = 0x40
    private static let msgStartupMessage: UInt8 = 0x6F

    // USB identifiers for common ANT+ sticks
    private static let antStickVendorIDs: [Int] = [0x0FCF]  // Dynastream (Garmin)
    private static let antStickProductIDs: [Int] = [0x1008, 0x1009]  // ANT USB-m, USB-2

    private var interface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBInterfaceInterface>>?
    private var deviceInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>>?
    private var readPipe: UInt8 = 0
    private var writePipe: UInt8 = 0
    private var running = false
    private var readThread: Thread?

    var onHeartRate: ((Int) -> Void)?
    var onStatusChange: ((String) -> Void)?

    private(set) var isConnected = false

    func start() {
        onStatusChange?("[ANT+] Searching for ANT+ USB stick...")

        guard findAndOpenANTStick() else {
            onStatusChange?("[ANT+] No ANT+ USB stick found. Make sure it's plugged in.")
            return
        }

        onStatusChange?("[ANT+] ANT+ stick found. Configuring...")
        isConnected = true

        configureANTChannel()

        running = true
        readThread = Thread {
            self.readLoop()
        }
        readThread?.name = "ANT+ Read Thread"
        readThread?.start()
    }

    func stop() {
        running = false
        readThread?.cancel()
        readThread = nil
        closeUSB()
        isConnected = false
    }

    // MARK: - USB Discovery (IOKit)

    private func findAndOpenANTStick() -> Bool {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var vendorID: Int = 0
            var productID: Int = 0

            if let vendorRef = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0) {
                vendorID = (vendorRef.takeRetainedValue() as? NSNumber)?.intValue ?? 0
            }
            if let productRef = IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0) {
                productID = (productRef.takeRetainedValue() as? NSNumber)?.intValue ?? 0
            }

            if Self.antStickVendorIDs.contains(vendorID) && Self.antStickProductIDs.contains(productID) {
                onStatusChange?("[ANT+] Found ANT+ stick (VID: \(String(format: "0x%04X", vendorID)), PID: \(String(format: "0x%04X", productID)))")
                return openDevice(service: service)
            }
        }
        return false
    }

    private func openDevice(service: io_service_t) -> Bool {
        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        let kr = IOCreatePlugInInterfaceForService(
            service,
            kIOUSBDeviceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugInInterface,
            &score
        )

        guard kr == KERN_SUCCESS, let plugIn = plugInInterface else {
            onStatusChange?("[ANT+] Failed to create plugin interface")
            return false
        }

        var deviceInterfacePtr: UnsafeMutableRawPointer?
        var usbDeviceInterfaceID = CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID)
        let queryResult = plugIn.pointee?.pointee.QueryInterface(
            plugIn,
            &usbDeviceInterfaceID,
            &deviceInterfacePtr
        )
        plugIn.pointee?.pointee.Release(plugIn)

        guard queryResult == S_OK,
              let rawDeviceInterface = deviceInterfacePtr else {
            onStatusChange?("[ANT+] Failed to get device interface")
            return false
        }

        let typedDevice = rawDeviceInterface.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBDeviceInterface>.self
        )
        self.deviceInterface = typedDevice

        // Open the device
        var openResult = typedDevice.pointee.pointee.USBDeviceOpen(typedDevice)
        if openResult != kIOReturnSuccess {
            // Try to seize it if already open
            openResult = typedDevice.pointee.pointee.USBDeviceOpenSeize(typedDevice)
            guard openResult == kIOReturnSuccess else {
                onStatusChange?("[ANT+] Cannot open USB device (error: \(openResult))")
                return false
            }
        }

        // Configure and find the interface
        return findInterface(device: typedDevice)
    }

    private func findInterface(device: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>>) -> Bool {
        // Set configuration
        var configDesc = IOUSBConfigurationDescriptorPtr(nil)
        device.pointee.pointee.GetConfigurationDescriptorPtr(device, 0, &configDesc)
        if let config = configDesc {
            device.pointee.pointee.SetConfiguration(device, config.pointee.bConfigurationValue)
        }

        var request = IOUSBFindInterfaceRequest(
            bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
            bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare),
            bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare)
        )

        var interfaceIterator: io_iterator_t = 0
        device.pointee.pointee.CreateInterfaceIterator(device, &request, &interfaceIterator)
        defer { IOObjectRelease(interfaceIterator) }

        let usbInterface = IOIteratorNext(interfaceIterator)
        guard usbInterface != 0 else {
            onStatusChange?("[ANT+] No USB interface found")
            return false
        }
        defer { IOObjectRelease(usbInterface) }

        var plugInInterface: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0

        IOCreatePlugInInterfaceForService(
            usbInterface,
            kIOUSBInterfaceUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugInInterface,
            &score
        )

        guard let plugIn = plugInInterface else { return false }

        var interfacePtr: UnsafeMutableRawPointer?
        var usbInterfaceID = CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID)
        plugIn.pointee?.pointee.QueryInterface(plugIn, &usbInterfaceID, &interfacePtr)
        plugIn.pointee?.pointee.Release(plugIn)

        guard let rawInterface = interfacePtr else { return false }

        let typedInterface = rawInterface.assumingMemoryBound(
            to: UnsafeMutablePointer<IOUSBInterfaceInterface>.self
        )
        self.interface = typedInterface

        typedInterface.pointee.pointee.USBInterfaceOpen(typedInterface)

        // Find endpoint pipes
        var numEndpoints: UInt8 = 0
        typedInterface.pointee.pointee.GetNumEndpoints(typedInterface, &numEndpoints)

        for i: UInt8 in 1...numEndpoints {
            var direction: UInt8 = 0
            var number: UInt8 = 0
            var transferType: UInt8 = 0
            var maxPacketSize: UInt16 = 0
            var interval: UInt8 = 0

            typedInterface.pointee.pointee.GetPipeProperties(
                typedInterface, i, &direction, &number, &transferType, &maxPacketSize, &interval
            )

            if direction == UInt8(kUSBIn) {
                readPipe = i
            } else if direction == UInt8(kUSBOut) {
                writePipe = i
            }
        }

        return readPipe != 0 && writePipe != 0
    }

    private func closeUSB() {
        if let iface = interface {
            iface.pointee.pointee.USBInterfaceClose(iface)
            iface.pointee.pointee.Release(iface)
            interface = nil
        }
        if let device = deviceInterface {
            device.pointee.pointee.USBDeviceClose(device)
            device.pointee.pointee.Release(device)
            deviceInterface = nil
        }
    }

    // MARK: - ANT+ Protocol

    private func buildMessage(type: UInt8, data: [UInt8]) -> [UInt8] {
        var msg: [UInt8] = [Self.antSyncByte, UInt8(data.count), type]
        msg.append(contentsOf: data)
        let checksum = msg.reduce(0 as UInt8) { $0 ^ $1 }
        msg.append(checksum)
        return msg
    }

    private func sendMessage(type: UInt8, data: [UInt8]) {
        let msg = buildMessage(type: type, data: data)
        guard let iface = interface else { return }

        var buffer = msg
        var size = UInt32(buffer.count)
        iface.pointee.pointee.WritePipe(iface, writePipe, &buffer, size)

        // Small delay between commands for the ANT+ stick to process
        usleep(50_000)
    }

    private func configureANTChannel() {
        // 1. Reset system
        sendMessage(type: Self.msgSystemReset, data: [0x00])
        usleep(500_000) // 500ms after reset

        // 2. Set network key on network 0
        var networkData: [UInt8] = [0x00] // network number
        networkData.append(contentsOf: Self.antNetworkKey)
        sendMessage(type: Self.msgSetNetworkKey, data: networkData)

        // 3. Assign channel 0 as receive (slave), network 0
        sendMessage(type: Self.msgAssignChannel, data: [0x00, 0x00, 0x00]) // channel, type=slave, network

        // 4. Set channel ID: device 0 (wildcard), device type 120 (HR), trans type 0 (wildcard)
        sendMessage(type: Self.msgSetChannelId, data: [
            0x00,                          // channel
            0x00, 0x00,                    // device number (wildcard = pair with any)
            Self.antHRDeviceType,          // device type
            0x00                           // transmission type (wildcard)
        ])

        // 5. Set channel RF frequency
        sendMessage(type: Self.msgSetChannelFreq, data: [0x00, Self.antRFFrequency])

        // 6. Set channel period
        sendMessage(type: Self.msgSetChannelPeriod, data: [
            0x00,
            UInt8(Self.antChannelPeriod & 0xFF),
            UInt8(Self.antChannelPeriod >> 8)
        ])

        // 7. Open channel
        sendMessage(type: Self.msgOpenChannel, data: [0x00])

        onStatusChange?("[ANT+] Channel configured. Waiting for HR strap...")
    }

    private func readLoop() {
        guard let iface = interface else { return }
        var buffer = [UInt8](repeating: 0, count: 64)

        while running {
            var bytesRead: UInt32 = UInt32(buffer.count)
            let result = iface.pointee.pointee.ReadPipe(iface, readPipe, &buffer, &bytesRead)

            if result == kIOReturnSuccess && bytesRead > 0 {
                parseANTMessages(Array(buffer[0..<Int(bytesRead)]))
            } else if result != kIOReturnSuccess {
                usleep(10_000) // Brief pause on error
            }
        }
    }

    private func parseANTMessages(_ data: [UInt8]) {
        var offset = 0
        while offset < data.count {
            guard data[offset] == Self.antSyncByte else {
                offset += 1
                continue
            }
            guard offset + 1 < data.count else { break }

            let length = Int(data[offset + 1])
            guard offset + 3 + length < data.count else { break }

            let msgType = data[offset + 2]
            let payload = Array(data[(offset + 3)..<(offset + 3 + length)])

            if msgType == Self.msgBroadcastData && length >= 9 {
                // ANT+ HR data page: payload[0] = channel, payload[1..8] = HR data
                // HR value is always in the last byte of the 8-byte data payload
                let heartRate = Int(payload[8])
                if heartRate > 0 {
                    DispatchQueue.main.async {
                        self.onHeartRate?(heartRate)
                    }
                }
            }

            offset += 4 + length // sync + len + type + payload + checksum
        }
    }
}
