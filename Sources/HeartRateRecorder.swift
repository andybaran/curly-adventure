import Foundation

/// Stores timestamped heart rate samples from any source.
final class HeartRateRecorder {

    struct Sample {
        let timestamp: Date
        let heartRate: Int
        let source: Source
    }

    enum Source: String {
        case ble = "BLE"
        case ant = "ANT+"
    }

    private(set) var samples: [Sample] = []
    private(set) var isRecording = false
    private(set) var startTime: Date?

    var currentHR: Int? {
        samples.last?.heartRate
    }

    var duration: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var averageHR: Int? {
        guard !samples.isEmpty else { return nil }
        let sum = samples.reduce(0) { $0 + $1.heartRate }
        return sum / samples.count
    }

    var maxHR: Int? {
        samples.map(\.heartRate).max()
    }

    var minHR: Int? {
        samples.map(\.heartRate).filter { $0 > 0 }.min()
    }

    func startRecording() {
        isRecording = true
        startTime = Date()
        samples.removeAll()
    }

    func stopRecording() {
        isRecording = false
    }

    /// Physiologically valid HR range. Values outside this are sensor noise.
    static let validHRRange = 30...250

    func addSample(heartRate: Int, source: Source) {
        guard isRecording, Self.validHRRange.contains(heartRate) else { return }
        let sample = Sample(timestamp: Date(), heartRate: heartRate, source: source)
        samples.append(sample)
    }
}
