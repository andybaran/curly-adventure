import Foundation

/// Exports heart rate data to Garmin .FIT file format.
///
/// FIT (Flexible and Interoperable Data Transfer) is Garmin's binary format.
/// This implements the minimum viable subset: file header, file ID message,
/// activity/session/lap summary, individual HR records, and CRC.
///
/// The exported file can be uploaded directly to Garmin Connect at:
///   https://connect.garmin.com/modern/import-data
final class FITExporter {

    // FIT epoch: Dec 31, 1989 00:00:00 UTC
    private static let fitEpoch = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "UTC"),
        year: 1989, month: 12, day: 31, hour: 0, minute: 0, second: 0
    ).date!

    private var data = Data()
    private var recordCount: UInt16 = 0

    // MARK: - Public

    func export(samples: [HeartRateRecorder.Sample], to url: URL) throws {
        guard !samples.isEmpty else {
            throw ExportError.noData
        }

        data = Data()
        recordCount = 0

        let startTime = samples.first!.timestamp
        let endTime = samples.last!.timestamp
        let elapsed = UInt32(endTime.timeIntervalSince(startTime))
        let avgHR = UInt8(samples.reduce(0) { $0 + $1.heartRate } / samples.count)
        let maxHR = UInt8(samples.map(\.heartRate).max() ?? 0)

        // Write messages (header placeholder, then data, then fix header)
        writeFileIdMessage(timestamp: startTime)
        writeEventMessage(timestamp: startTime, eventType: 0) // start event
        writeLapMessage(timestamp: endTime, startTime: startTime, elapsed: elapsed, avgHR: avgHR, maxHR: maxHR)

        for sample in samples {
            writeRecordMessage(timestamp: sample.timestamp, heartRate: UInt8(min(sample.heartRate, 255)))
        }

        writeEventMessage(timestamp: endTime, eventType: 4) // stop event
        writeSessionMessage(timestamp: endTime, startTime: startTime, elapsed: elapsed, avgHR: avgHR, maxHR: maxHR)
        writeActivityMessage(timestamp: endTime, elapsed: elapsed)

        // Build final file: header + data + CRC
        let fileData = buildFile()
        try fileData.write(to: url)
    }

    enum ExportError: Error, LocalizedError {
        case noData

        var errorDescription: String? {
            switch self {
            case .noData: return "No heart rate data to export"
            }
        }
    }

    // MARK: - FIT File Structure

    private func buildFile() -> Data {
        var file = Data()

        // 14-byte file header
        let dataSize = UInt32(data.count)
        file.append(14)                          // header size
        file.append(UInt8(20))                   // protocol version (2.0)
        file.appendUInt16(2147)                  // profile version (21.47)
        file.appendUInt32(dataSize)              // data size
        file.append(contentsOf: [0x2E, 0x46, 0x49, 0x54]) // ".FIT"
        let headerCRC = crc16(Data(file[0..<12]))
        file.appendUInt16(headerCRC)

        // Data records
        file.append(data)

        // File CRC (over header + data)
        let fileCRC = crc16(file)
        file.appendUInt16(fileCRC)

        return file
    }

    // MARK: - FIT Messages

    /// File ID message (mesg num 0) — required first message
    private func writeFileIdMessage(timestamp: Date) {
        // Definition message for local message 0
        writeDefinitionMessage(
            localMesg: 0,
            globalMesgNum: 0, // file_id
            fields: [
                (fieldNum: 0, size: 1, baseType: 0x00), // type: enum (activity=4)
                (fieldNum: 1, size: 2, baseType: 0x84), // manufacturer: uint16
                (fieldNum: 2, size: 2, baseType: 0x84), // product: uint16
                (fieldNum: 3, size: 4, baseType: 0x86), // serial_number: uint32z
                (fieldNum: 4, size: 4, baseType: 0x86), // time_created: uint32
            ]
        )

        // Data message
        var msg = Data()
        msg.append(0x00) // record header: local message 0
        msg.append(4)    // type = activity
        msg.appendUInt16(1)  // manufacturer = Garmin
        msg.appendUInt16(1)  // product
        msg.appendUInt32(12345) // serial number
        msg.appendUInt32(fitTimestamp(timestamp))
        data.append(msg)
        recordCount += 1
    }

    /// Event message (mesg num 21)
    private func writeEventMessage(timestamp: Date, eventType: UInt8) {
        writeDefinitionMessage(
            localMesg: 1,
            globalMesgNum: 21,
            fields: [
                (fieldNum: 253, size: 4, baseType: 0x86), // timestamp
                (fieldNum: 0, size: 1, baseType: 0x00),   // event (timer=0)
                (fieldNum: 1, size: 1, baseType: 0x00),   // event_type
            ]
        )

        var msg = Data()
        msg.append(0x01)
        msg.appendUInt32(fitTimestamp(timestamp))
        msg.append(0)         // event = timer
        msg.append(eventType) // 0=start, 4=stop
        data.append(msg)
        recordCount += 1
    }

    /// Record message (mesg num 20) — individual data points
    private func writeRecordMessage(timestamp: Date, heartRate: UInt8) {
        writeDefinitionMessage(
            localMesg: 2,
            globalMesgNum: 20,
            fields: [
                (fieldNum: 253, size: 4, baseType: 0x86), // timestamp
                (fieldNum: 3, size: 1, baseType: 0x02),   // heart_rate: uint8
            ]
        )

        var msg = Data()
        msg.append(0x02) // local message 2
        msg.appendUInt32(fitTimestamp(timestamp))
        msg.append(heartRate)
        data.append(msg)
        recordCount += 1
    }

    /// Lap message (mesg num 19)
    private func writeLapMessage(timestamp: Date, startTime: Date, elapsed: UInt32, avgHR: UInt8, maxHR: UInt8) {
        writeDefinitionMessage(
            localMesg: 3,
            globalMesgNum: 19,
            fields: [
                (fieldNum: 253, size: 4, baseType: 0x86), // timestamp
                (fieldNum: 2, size: 4, baseType: 0x86),   // start_time
                (fieldNum: 7, size: 4, baseType: 0x86),   // total_elapsed_time (ms)
                (fieldNum: 8, size: 4, baseType: 0x86),   // total_timer_time (ms)
                (fieldNum: 15, size: 1, baseType: 0x02),  // avg_heart_rate
                (fieldNum: 16, size: 1, baseType: 0x02),  // max_heart_rate
                (fieldNum: 24, size: 1, baseType: 0x00),  // lap_trigger
                (fieldNum: 25, size: 1, baseType: 0x00),  // sport
            ]
        )

        var msg = Data()
        msg.append(0x03)
        msg.appendUInt32(fitTimestamp(timestamp))
        msg.appendUInt32(fitTimestamp(startTime))
        msg.appendUInt32(elapsed * 1000) // total_elapsed_time in ms
        msg.appendUInt32(elapsed * 1000) // total_timer_time in ms
        msg.append(avgHR)
        msg.append(maxHR)
        msg.append(0) // lap_trigger = manual
        msg.append(0) // sport = generic
        data.append(msg)
        recordCount += 1
    }

    /// Session message (mesg num 18)
    private func writeSessionMessage(timestamp: Date, startTime: Date, elapsed: UInt32, avgHR: UInt8, maxHR: UInt8) {
        writeDefinitionMessage(
            localMesg: 4,
            globalMesgNum: 18,
            fields: [
                (fieldNum: 253, size: 4, baseType: 0x86), // timestamp
                (fieldNum: 2, size: 4, baseType: 0x86),   // start_time
                (fieldNum: 7, size: 4, baseType: 0x86),   // total_elapsed_time
                (fieldNum: 8, size: 4, baseType: 0x86),   // total_timer_time
                (fieldNum: 16, size: 1, baseType: 0x02),  // avg_heart_rate
                (fieldNum: 17, size: 1, baseType: 0x02),  // max_heart_rate
                (fieldNum: 5, size: 1, baseType: 0x00),   // sport
                (fieldNum: 6, size: 1, baseType: 0x00),   // sub_sport
                (fieldNum: 25, size: 2, baseType: 0x84),  // first_lap_index
                (fieldNum: 26, size: 2, baseType: 0x84),  // num_laps
                (fieldNum: 27, size: 1, baseType: 0x00),  // trigger
            ]
        )

        var msg = Data()
        msg.append(0x04)
        msg.appendUInt32(fitTimestamp(timestamp))
        msg.appendUInt32(fitTimestamp(startTime))
        msg.appendUInt32(elapsed * 1000)
        msg.appendUInt32(elapsed * 1000)
        msg.append(avgHR)
        msg.append(maxHR)
        msg.append(0)  // sport = generic
        msg.append(0)  // sub_sport = generic
        msg.appendUInt16(0) // first_lap_index
        msg.appendUInt16(1) // num_laps
        msg.append(0)  // trigger = activity_end
        data.append(msg)
        recordCount += 1
    }

    /// Activity message (mesg num 34)
    private func writeActivityMessage(timestamp: Date, elapsed: UInt32) {
        writeDefinitionMessage(
            localMesg: 5,
            globalMesgNum: 34,
            fields: [
                (fieldNum: 253, size: 4, baseType: 0x86), // timestamp
                (fieldNum: 0, size: 4, baseType: 0x86),   // total_timer_time (s * 1000)
                (fieldNum: 1, size: 2, baseType: 0x84),   // num_sessions
                (fieldNum: 2, size: 1, baseType: 0x00),   // type (manual=0)
                (fieldNum: 3, size: 1, baseType: 0x00),   // event (activity=26)
                (fieldNum: 4, size: 1, baseType: 0x00),   // event_type (stop=1)
            ]
        )

        var msg = Data()
        msg.append(0x05)
        msg.appendUInt32(fitTimestamp(timestamp))
        msg.appendUInt32(elapsed * 1000)
        msg.appendUInt16(1) // num_sessions
        msg.append(0)       // type = manual
        msg.append(26)      // event = activity
        msg.append(1)       // event_type = stop
        data.append(msg)
        recordCount += 1
    }

    // MARK: - Definition Message Writer

    private func writeDefinitionMessage(
        localMesg: UInt8,
        globalMesgNum: UInt16,
        fields: [(fieldNum: UInt8, size: UInt8, baseType: UInt8)]
    ) {
        var def = Data()
        def.append(0x40 | localMesg) // definition record header
        def.append(0)                 // reserved
        def.append(0)                 // architecture: little-endian
        def.appendUInt16(globalMesgNum)
        def.append(UInt8(fields.count))
        for field in fields {
            def.append(field.fieldNum)
            def.append(field.size)
            def.append(field.baseType)
        }
        data.append(def)
    }

    // MARK: - Helpers

    private func fitTimestamp(_ date: Date) -> UInt32 {
        return UInt32(date.timeIntervalSince(Self.fitEpoch))
    }

    /// CRC-16 used in FIT files (CRC-16/CCITT with poly 0x1021)
    private func crc16(_ data: Data) -> UInt16 {
        let crcTable: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
        ]

        var crc: UInt16 = 0
        for byte in data {
            let b = UInt16(byte)
            // Process low nibble
            var tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int(b & 0xF)]
            // Process high nibble
            tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int((b >> 4) & 0xF)]
        }
        return crc
    }
}

// MARK: - Data Helpers

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
