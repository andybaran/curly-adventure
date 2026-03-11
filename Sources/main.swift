import Foundation

// ============================================================================
// Heart Rate Recorder for macOS (Apple Silicon)
//
// Connects to BLE (Wahoo) and ANT+ (Garmin) heart rate monitors simultaneously.
// Displays real-time HR in the terminal and exports to .FIT for Garmin Connect.
// ============================================================================

let recorder = HeartRateRecorder()
let bleMonitor = BLEHeartRateMonitor()
let antMonitor = ANTHeartRateMonitor()
let exporter = FITExporter()
let arnold = ArnoldCoach()

var lastBLEHR: Int?
var lastANTHR: Int?
var displayTimer: Timer?

// MARK: - Terminal Display

func clearLine() {
    print("\u{1B}[2K\r", terminator: "")
}

func moveCursorUp(_ n: Int) {
    if n > 0 {
        print("\u{1B}[\(n)A", terminator: "")
    }
}

let displayLines = 15  // Number of lines in our display block

func renderDisplay() {
    moveCursorUp(displayLines)

    let hr = recorder.currentHR ?? lastBLEHR ?? lastANTHR
    let hrStr = hr.map { "\($0) bpm" } ?? "---"
    let avgStr = recorder.averageHR.map { "\($0) bpm" } ?? "---"
    let maxStr = recorder.maxHR.map { "\($0) bpm" } ?? "---"
    let minStr = recorder.minHR.map { "\($0) bpm" } ?? "---"
    let samplesStr = "\(recorder.samples.count)"

    let elapsed = recorder.duration
    let mins = Int(elapsed) / 60
    let secs = Int(elapsed) % 60
    let durationStr = recorder.isRecording ? String(format: "%02d:%02d", mins, secs) : "--:--"

    let bleStatus = bleMonitor.isConnected ? "Connected" : "Searching..."
    let antStatus = antMonitor.isConnected ? "Connected" : "Searching..."
    let recStatus = recorder.isRecording ? "● RECORDING" : "○ Stopped"
    let arnoldStatus = arnold.enabled ? "ON" : "OFF"

    let lines = [
        "╔══════════════════════════════════════════════╗",
        "║      ❤ Heart Rate Recorder (Arnold Ed.)     ║",
        "╠══════════════════════════════════════════════╣",
        "║  Current HR:  \(pad(hrStr, 30))║",
        "║  Average HR:  \(pad(avgStr, 30))║",
        "║  Max HR:      \(pad(maxStr, 30))║",
        "║  Min HR:      \(pad(minStr, 30))║",
        "║  Duration:    \(pad(durationStr, 30))║",
        "║  Samples:     \(pad(samplesStr, 30))║",
        "╠══════════════════════════════════════════════╣",
        "║  BLE:  \(pad(bleStatus, 37))║",
        "║  ANT+: \(pad(antStatus, 37))║",
        "║  Status: \(pad(recStatus, 35))║",
        "║  Arnold: \(pad(arnoldStatus, 35))║",
        "╚══════════════════════════════════════════════╝",
    ]

    for line in lines {
        clearLine()
        print(line)
    }
}

func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return String(s.prefix(width)) }
    return s + String(repeating: " ", count: width - s.count)
}

func printStatus(_ msg: String) {
    // Print status below the box
    print("  \(msg)")
}

// MARK: - BLE Callbacks

bleMonitor.onHeartRate = { hr in
    lastBLEHR = hr
    recorder.addSample(heartRate: hr, source: .ble)
    if recorder.isRecording { arnold.processHeartRate(hr) }
}

bleMonitor.onStatusChange = { msg in
    printStatus(msg)
}

bleMonitor.onDeviceFound = { msg in
    printStatus(msg)
}

// MARK: - ANT+ Callbacks

antMonitor.onHeartRate = { hr in
    lastANTHR = hr
    recorder.addSample(heartRate: hr, source: .ant)
    if recorder.isRecording { arnold.processHeartRate(hr) }
}

antMonitor.onStatusChange = { msg in
    printStatus(msg)
}

// MARK: - Commands

func printHelp() {
    print("""

    Commands:
      r / record   - Start recording
      s / stop     - Stop recording
      e / export   - Export to .FIT file
      a / arnold   - Toggle Arnold voice coach on/off
      v / voice    - Cycle through available voices
      q / quit     - Stop and exit
      h / help     - Show this help

    """)
}

func exportData() {
    guard !recorder.samples.isEmpty else {
        print("  No data to export. Record some data first.")
        return
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HHmmss"
    let filename = "heart_rate_\(formatter.string(from: Date())).fit"

    let url: URL
    if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
        url = downloads.appendingPathComponent(filename)
    } else {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(filename)
    }

    do {
        try exporter.export(samples: recorder.samples, to: url)
        print("  Exported \(recorder.samples.count) samples to: \(url.path)")
        print("  Upload to Garmin Connect at: https://connect.garmin.com/modern/import-data")
    } catch {
        print("  Export failed: \(error.localizedDescription)")
    }
}

// MARK: - Main

print("""

  Heart Rate Recorder — macOS (Apple Silicon)
  ============================================
  Searching for heart rate monitors...
  - BLE: Wahoo / any Bluetooth HR strap
  - ANT+: Garmin / any ANT+ HR strap (via USB stick)

  Type 'h' for help, 'r' to start recording.

""")

// Print initial blank display area
for _ in 0..<displayLines {
    print()
}

// Start monitors
bleMonitor.startScanning()
antMonitor.start()

// Start display refresh timer (every 1 second)
displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    renderDisplay()
}

// Handle stdin for commands
let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
stdinSource.setEventHandler {
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return }

    switch line {
    case "r", "record":
        recorder.startRecording()
        arnold.speakEvent("Let's go! Time to pump that heart! Recording has started!")
        printStatus("Recording started. Press 's' to stop.")
    case "s", "stop":
        recorder.stopRecording()
        arnold.speakEvent("Great workout! You are a champion! Now rest, and come back even stronger!")
        printStatus("Recording stopped. \(recorder.samples.count) samples captured.")
    case "e", "export":
        exportData()
    case "q", "quit", "exit":
        recorder.stopRecording()
        if !recorder.samples.isEmpty {
            print("  Auto-exporting before exit...")
            exportData()
        }
        bleMonitor.stop()
        antMonitor.stop()
        displayTimer?.invalidate()
        print("  Goodbye!")
        exit(0)
    case "a", "arnold":
        let newState = !arnold.enabled
        arnold.setEnabled(newState)
        if newState {
            arnold.speakEvent("Arnold is back! I will push you to the limit!")
        }
        printStatus("Arnold coach: \(newState ? "ON" : "OFF")")
    case "v", "voice":
        let voices = ["Alex", "Daniel", "Fred", "Ralph", "Rishi"]
        let currentIdx = voices.firstIndex(of: arnold.voice) ?? 0
        let nextIdx = (currentIdx + 1) % voices.count
        arnold.voice = voices[nextIdx]
        arnold.speakEvent("This is \(arnold.voice). I will be your Arnold today!")
        printStatus("Voice changed to: \(arnold.voice)")
    case "h", "help":
        printHelp()
    default:
        printStatus("Unknown command: '\(line)'. Type 'h' for help.")
    }
}
stdinSource.resume()

// Entitlements note
printStatus("Note: If BLE scanning fails, the app needs Bluetooth permission.")
printStatus("      Build with: swift build -c release")
printStatus("      Run with:   .build/release/HeartRateRecorder")

// Run the main run loop
RunLoop.main.run()
