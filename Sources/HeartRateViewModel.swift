import Foundation
import Combine
import SwiftUI

final class HeartRateViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentHR: Int = 0
    @Published var averageHR: Int = 0
    @Published var maxHR: Int = 0
    @Published var minHR: Int = 0
    @Published var isRecording: Bool = false
    @Published var isBLEConnected: Bool = false
    @Published var isANTConnected: Bool = false
    @Published var bleDeviceName: String = ""
    @Published var statusMessages: [StatusMessage] = []
    @Published var arnoldEnabled: Bool = true
    @Published var arnoldMuted: Bool = false
    @Published var voiceName: String = "Alex"
    @Published var sampleCount: Int = 0
    @Published var duration: TimeInterval = 0
    @Published var currentZone: HRZone = .rest
    @Published var lastExportPath: String = ""

    // MARK: - Types

    struct StatusMessage: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
    }

    enum HRZone: String, CaseIterable {
        case rest = "REST"
        case warmUp = "WARM UP"
        case fatBurn = "FAT BURN"
        case cardio = "CARDIO"
        case peak = "PEAK"
        case max = "MAX"

        var color: Color {
            switch self {
            case .rest:    return .gray
            case .warmUp:  return .blue
            case .fatBurn: return .green
            case .cardio:  return .orange
            case .peak:    return .red
            case .max:     return .purple
            }
        }

        static func from(hr: Int) -> HRZone {
            switch hr {
            case ..<100:  return .rest
            case 100..<120: return .warmUp
            case 120..<140: return .fatBurn
            case 140..<160: return .cardio
            case 160..<190: return .peak
            default:        return .max
            }
        }

        /// Fractional position (0-1) in the zone bar
        static func fraction(hr: Int) -> CGFloat {
            let clamped = Swift.min(Swift.max(CGFloat(hr), 40), 220)
            return (clamped - 40) / 180.0
        }
    }

    // MARK: - Private Models

    private let recorder = HeartRateRecorder()
    private let bleMonitor = BLEHeartRateMonitor()
    private let antMonitor = ANTHeartRateMonitor()
    private let exporter = FITExporter()
    private let coach = ArnoldCoach()

    private var updateTimer: Timer?
    private var autoSaveTimer: Timer?

    private var lastBLEHR: Int = 0
    private var lastBLETime: Date = .distantPast
    private var lastANTHR: Int = 0
    private var lastANTTime: Date = .distantPast
    private let staleThreshold: TimeInterval = 5

    private let voices = ["Alex", "Daniel", "Fred", "Ralph", "Rishi"]
    private var voiceIndex = 0

    // MARK: - Init

    init() {
        setupMonitors()
        startUpdateTimer()
    }

    // MARK: - Setup

    private func setupMonitors() {
        bleMonitor.onHeartRate = { [weak self] hr in
            guard let self else { return }
            self.lastBLEHR = hr
            self.lastBLETime = Date()
            self.currentHR = hr
            self.currentZone = HRZone.from(hr: hr)
            self.processHeartRate(hr, source: .ble)
        }
        bleMonitor.onStatusChange = { [weak self] msg in
            self?.addStatus(msg)
        }
        bleMonitor.onDeviceFound = { [weak self] name in
            self?.bleDeviceName = name
        }

        antMonitor.onHeartRate = { [weak self] hr in
            guard let self else { return }
            self.lastANTHR = hr
            self.lastANTTime = Date()
            // Only update display from ANT+ if BLE is stale
            if Date().timeIntervalSince(self.lastBLETime) >= self.staleThreshold {
                self.currentHR = hr
                self.currentZone = HRZone.from(hr: hr)
            }
            self.processHeartRate(hr, source: .ant)
        }
        antMonitor.onStatusChange = { [weak self] msg in
            self?.addStatus(msg)
        }

        bleMonitor.startScanning()
        antMonitor.start()

        addStatus("Heart Rate Recorder started. Scanning for monitors...")
        addStatus(coach.clipStatus)
    }

    private func startUpdateTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        isBLEConnected = bleMonitor.isConnected
        isANTConnected = antMonitor.isConnected

        // Clear display if data is stale
        let now = Date()
        let bleOK = now.timeIntervalSince(lastBLETime) < staleThreshold
        let antOK = now.timeIntervalSince(lastANTTime) < staleThreshold
        if !bleOK && !antOK {
            currentHR = 0
            currentZone = .rest
        }

        if isRecording {
            duration = recorder.duration
            sampleCount = recorder.samples.count
            averageHR = recorder.averageHR ?? 0
            maxHR = recorder.maxHR ?? 0
            minHR = recorder.minHR ?? 0
        }
    }

    private func processHeartRate(_ hr: Int, source: HeartRateRecorder.Source) {
        if recorder.isRecording {
            recorder.addSample(heartRate: hr, source: source)
        }
        if arnoldEnabled {
            coach.processHeartRate(hr)
        }
    }

    // MARK: - Actions

    func startRecording() {
        recorder.startRecording()
        isRecording = true
        sampleCount = 0
        averageHR = 0
        maxHR = 0
        minHR = 0
        duration = 0
        lastExportPath = ""
        addStatus("Recording started")

        if arnoldEnabled {
            coach.speakEvent("Let's go! Time to pump it up! Recording started!", clipFolder: "start")
        }

        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.autoSave()
        }
    }

    func stopRecording() {
        recorder.stopRecording()
        isRecording = false
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        addStatus("Recording stopped (\(recorder.samples.count) samples)")

        if arnoldEnabled {
            coach.speakEvent("Great workout! You are a champion!", clipFolder: "stop")
        }

        if !recorder.samples.isEmpty {
            exportFIT()
        }
    }

    func exportFIT() {
        guard !recorder.samples.isEmpty else {
            addStatus("No data to export")
            return
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "heart_rate_\(fmt.string(from: Date())).fit"

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = downloadsURL.appendingPathComponent(filename)

        do {
            try exporter.export(samples: recorder.samples, to: url)
            lastExportPath = url.path
            addStatus("Exported: \(url.lastPathComponent)")
        } catch {
            addStatus("Export failed: \(error.localizedDescription)")
        }

        // Clean up auto-save
        let autoSaveURL = downloadsURL.appendingPathComponent("heart_rate_autosave.fit")
        try? FileManager.default.removeItem(at: autoSaveURL)
    }

    func toggleArnold() {
        arnoldEnabled.toggle()
        coach.setEnabled(arnoldEnabled)
        addStatus("Arnold coach \(arnoldEnabled ? "enabled" : "disabled")")
    }

    func toggleMute() {
        arnoldMuted = coach.toggleMute()
        addStatus("Voice \(arnoldMuted ? "muted" : "unmuted")")
    }

    func cycleVoice() {
        voiceIndex = (voiceIndex + 1) % voices.count
        voiceName = voices[voiceIndex]
        coach.voice = voiceName
        addStatus("Voice: \(voiceName)")
    }

    // MARK: - Helpers

    private func addStatus(_ text: String) {
        let msg = StatusMessage(text: text, timestamp: Date())
        statusMessages.append(msg)
        if statusMessages.count > 100 {
            statusMessages.removeFirst(statusMessages.count - 100)
        }
    }

    private func autoSave() {
        guard !recorder.samples.isEmpty else { return }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = downloadsURL.appendingPathComponent("heart_rate_autosave.fit")
        try? exporter.export(samples: recorder.samples, to: url)
    }

    func cleanup() {
        updateTimer?.invalidate()
        autoSaveTimer?.invalidate()
        if recorder.isRecording {
            recorder.stopRecording()
            if !recorder.samples.isEmpty {
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.homeDirectoryForCurrentUser
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd_HHmmss"
                let filename = "heart_rate_\(fmt.string(from: Date())).fit"
                let url = downloadsURL.appendingPathComponent(filename)
                try? exporter.export(samples: recorder.samples, to: url)
            }
        }
        bleMonitor.stop()
        antMonitor.stop()
    }
}
