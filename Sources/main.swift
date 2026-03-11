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

// ============================================================================
// MARK: - ANSI Color Codes (Hospital Monitor Palette)
// ============================================================================

struct C {
    static let reset     = "\u{1B}[0m"
    static let bold      = "\u{1B}[1m"
    static let dim       = "\u{1B}[2m"

    // Green phosphor (primary ECG trace + HR)
    static let green     = "\u{1B}[38;2;0;255;65m"
    static let greenDim  = "\u{1B}[38;2;0;140;35m"
    static let greenBg   = "\u{1B}[48;2;0;30;5m"

    // Amber/yellow (warnings, secondary vitals)
    static let amber     = "\u{1B}[38;2;255;191;0m"
    static let amberDim  = "\u{1B}[38;2;140;105;0m"

    // Cyan (SpO2 channel style)
    static let cyan      = "\u{1B}[38;2;0;220;255m"
    static let cyanDim   = "\u{1B}[38;2;0;110;130m"

    // Red (alerts, recording indicator)
    static let red       = "\u{1B}[38;2;255;50;50m"
    static let redBright = "\u{1B}[38;2;255;0;0m"

    // Monitor chrome (dark bezels)
    static let chrome    = "\u{1B}[38;2;60;65;70m"
    static let chromeLt  = "\u{1B}[38;2;90;95;100m"
    static let bgDark    = "\u{1B}[48;2;8;10;8m"
    static let bgPanel   = "\u{1B}[48;2;12;15;12m"

    // White for labels
    static let white     = "\u{1B}[38;2;180;185;180m"
    static let whiteDim  = "\u{1B}[38;2;100;105;100m"
}

// ============================================================================
// MARK: - Big Block Digits (7-segment style, 5 tall x 4 wide)
// ============================================================================

let bigDigits: [Character: [String]] = [
    "0": ["┏━━┓", "┃  ┃", "┃  ┃", "┃  ┃", "┗━━┛"],
    "1": ["   ┐", "   │", "   │", "   │", "   ╵"],
    "2": ["╶━━┓", "   ┃", "┏━━┛", "┃   ", "┗━━╴"],
    "3": ["╶━━┓", "   ┃", "╶━━┫", "   ┃", "╶━━┛"],
    "4": ["╷  ╷", "┃  ┃", "┗━━┫", "   ┃", "   ╵"],
    "5": ["┏━━╴", "┃   ", "┗━━┓", "   ┃", "╶━━┛"],
    "6": ["┏━━╴", "┃   ", "┣━━┓", "┃  ┃", "┗━━┛"],
    "7": ["╶━━┓", "   ┃", "   ┃", "   ┃", "   ╵"],
    "8": ["┏━━┓", "┃  ┃", "┣━━┫", "┃  ┃", "┗━━┛"],
    "9": ["┏━━┓", "┃  ┃", "┗━━┫", "   ┃", "╶━━┛"],
    "-": ["    ", "    ", "╶━━╴", "    ", "    "],
]

func renderBigNumber(_ text: String, color: String) -> [String] {
    var lines = ["", "", "", "", ""]
    for ch in text {
        let glyph = bigDigits[ch] ?? ["    ", "    ", "    ", "    ", "    "]
        for row in 0..<5 {
            lines[row] += color + glyph[row] + " "
        }
    }
    return lines
}

// ============================================================================
// MARK: - ECG Waveform Generator
// ============================================================================

/// A single PQRST complex waveform pattern (heights mapped to row offsets).
/// Values represent vertical position: 0 = baseline, positive = up, negative = down.
/// The pattern repeats based on heart rate.
let pqrstPattern: [Int] = [
    // Flat baseline
    0, 0, 0, 0,
    // P wave (small bump)
    0, 1, 2, 2, 1, 0,
    // PR segment
    0, 0,
    // QRS complex (sharp spike)
    0, -1, -2, 6, 8, 9, 8, 4, -3, -2, -1,
    // ST segment
    0, 0, 0,
    // T wave (medium bump)
    0, 1, 2, 3, 3, 2, 1, 0,
    // Baseline
    0, 0, 0, 0, 0, 0,
]

let waveformWidth = 62
var waveformBuffer: [Int] = Array(repeating: 0, count: waveformWidth)
var waveformPhase: Int = 0
var beatAnimFrame: Int = 0  // For pulsing heart icon

/// Advance the ECG waveform by one step, injecting the PQRST pattern.
func advanceWaveform(heartRate: Int?) {
    // Calculate how many columns per beat based on HR
    // At 60 bpm, 1 beat/sec at ~4 columns/refresh = ~60 cols per beat
    // Scale pattern to fit: repeat baseline to fill gap between complexes
    let patternLen = pqrstPattern.count
    let totalCycleLen: Int
    if let hr = heartRate, hr > 0 {
        // At our refresh rate (~4 cols/sec), map HR to cycle length
        totalCycleLen = max(patternLen + 4, Int(240.0 / Double(hr) * Double(patternLen)))
    } else {
        totalCycleLen = patternLen + 30 // Slow default
    }

    // Generate next few columns
    let colsPerTick = 3
    for _ in 0..<colsPerTick {
        let posInCycle = waveformPhase % totalCycleLen
        let value: Int
        if posInCycle < patternLen {
            value = pqrstPattern[posInCycle]
        } else {
            value = 0 // Flat baseline between beats
        }
        waveformBuffer.removeFirst()
        waveformBuffer.append(value)
        waveformPhase += 1
    }

    // Trigger beat animation on the R-wave peak
    let posInCycle = waveformPhase % totalCycleLen
    if posInCycle >= 12 && posInCycle <= 16 {
        beatAnimFrame = 4
    } else if beatAnimFrame > 0 {
        beatAnimFrame -= 1
    }
}

/// Render the waveform buffer into rows of characters.
/// Returns an array of strings, one per row (top to bottom).
func renderWaveform(rows: Int) -> [String] {
    let minVal = -3
    let maxVal = 9
    let range = maxVal - minVal
    var grid = Array(repeating: Array(repeating: " ", count: waveformWidth), count: rows)
    let baselineRow = Int(Double(rows - 1) * Double(maxVal) / Double(range))

    for col in 0..<waveformWidth {
        let val = waveformBuffer[col]
        let row = baselineRow - Int(Double(val) / Double(range) * Double(rows - 1))
        let clampedRow = max(0, min(rows - 1, row))

        // Draw the trace point
        grid[clampedRow][col] = "█"

        // Draw a faint trail below the trace for phosphor glow effect
        if clampedRow > 0 && clampedRow < rows - 1 {
            let aboveRow = clampedRow - 1
            let belowRow = clampedRow + 1
            if grid[belowRow][col] == " " { grid[belowRow][col] = "░" }
            if val > 4 && grid[aboveRow][col] == " " { grid[aboveRow][col] = "░" }
        }
    }

    // Render with color
    var lines: [String] = []
    for row in 0..<rows {
        var line = ""
        for col in 0..<waveformWidth {
            let ch = grid[row][col]
            switch ch {
            case "█":
                // Bright green for recent columns, dimmer for older
                let brightness = Double(col) / Double(waveformWidth)
                if brightness > 0.85 {
                    line += C.green + C.bold + ch
                } else if brightness > 0.5 {
                    line += C.green + ch
                } else {
                    line += C.greenDim + ch
                }
            case "░":
                line += C.greenDim + ch
            default:
                line += C.reset + C.bgDark + " "
            }
        }
        line += C.reset
        lines.append(line)
    }

    return lines
}

// ============================================================================
// MARK: - Terminal Display (Hospital Monitor)
// ============================================================================

let displayLines = 30

func moveCursorUp(_ n: Int) {
    if n > 0 { print("\u{1B}[\(n)A", terminator: "") }
}

func clearLine() {
    print("\u{1B}[2K\r", terminator: "")
}

func pad(_ s: String, _ width: Int) -> String {
    if s.count >= width { return String(s.prefix(width)) }
    return s + String(repeating: " ", count: width - s.count)
}

func padLeft(_ s: String, _ width: Int) -> String {
    if s.count >= width { return String(s.prefix(width)) }
    return String(repeating: " ", count: width - s.count) + s
}

func renderDisplay() {
    moveCursorUp(displayLines)

    let hr = recorder.currentHR ?? lastBLEHR ?? lastANTHR
    let elapsed = recorder.duration
    let mins = Int(elapsed) / 60
    let secs = Int(elapsed) % 60

    // Advance waveform
    advanceWaveform(heartRate: hr)

    // Pulsing heart icon
    let heartIcon: String
    if hr != nil {
        heartIcon = beatAnimFrame > 2
            ? C.redBright + C.bold + "♥"
            : (beatAnimFrame > 0 ? C.red + "♥" : C.red + C.dim + "♥")
    } else {
        heartIcon = C.whiteDim + "♡"
    }

    // ── Build the display ──
    var output = ""

    func line(_ s: String) {
        output += "\u{1B}[2K" + s + C.reset + "\n"
    }

    let w = 78  // Total width

    // ┌─ Top bezel ─┐
    line("\(C.chrome)┌\(String(repeating: "─", count: w - 2))┐")
    line("\(C.chrome)│\(C.bgDark)\(C.chromeLt)  CARDIAC MONITOR  \(C.whiteDim)MODEL HR-1000A\(C.chromeLt)          ● REC: \(recorder.isRecording ? "\(C.red)▶ ACTIVE" : "\(C.whiteDim)■ IDLE  ")\(C.chromeLt)    ARNOLD: \(arnold.enabled ? "\(C.amber)ON " : "\(C.whiteDim)OFF")\(C.reset)\(C.bgDark) \(C.chrome)│")

    // ┌─ ECG Section Header ─┐
    line("\(C.chrome)│\(C.bgDark)\(C.green) ╶─ ECG ─── LEAD II ──────────────────────────────────────────────────────\(C.reset)\(C.bgDark) \(C.chrome)│")

    // ECG Waveform (9 rows)
    let waveRows = renderWaveform(rows: 9)
    for waveRow in waveRows {
        line("\(C.chrome)│\(C.bgDark) \(waveRow)\(C.bgDark)               \(C.chrome)│")
    }

    // Divider
    line("\(C.chrome)│\(C.bgDark)\(C.chrome) ─────────────────────────────────────────────────────────────────────────── \(C.chrome)│")

    // ┌─ Vitals Panel ─┐
    // Large HR number
    let hrString = hr.map { "\($0)" } ?? "---"
    let bigHR = renderBigNumber(hrString, color: C.green + C.bold)

    // Stats column
    let avgStr = recorder.averageHR.map { "\($0)" } ?? "--"
    let maxStr = recorder.maxHR.map { "\($0)" } ?? "--"
    let minStr = recorder.minHR.map { "\($0)" } ?? "--"
    let durStr = recorder.isRecording ? String(format: "%02d:%02d", mins, secs) : "--:--"
    let sampStr = "\(recorder.samples.count)"
    let bleStr = bleMonitor.isConnected ? "\(C.green)●\(C.white) BLE" : "\(C.amberDim)○\(C.whiteDim) BLE"
    let antStr = antMonitor.isConnected ? "\(C.cyan)●\(C.white) ANT+" : "\(C.amberDim)○\(C.whiteDim) ANT+"

    // Row 0 of vitals: HR label + big digit row 0 + stats header
    line("\(C.chrome)│\(C.bgDark) \(heartIcon) \(C.green)HR\(C.whiteDim) bpm      \(bigHR[0])\(C.reset)\(C.bgDark)      \(C.amber)AVG  \(C.amber + C.bold)\(padLeft(avgStr, 3))\(C.reset)\(C.bgDark) \(C.whiteDim)bpm   \(C.chrome)│")
    line("\(C.chrome)│\(C.bgDark)              \(bigHR[1])\(C.reset)\(C.bgDark)      \(C.red)MAX  \(C.red + C.bold)\(padLeft(maxStr, 3))\(C.reset)\(C.bgDark) \(C.whiteDim)bpm   \(C.chrome)│")
    line("\(C.chrome)│\(C.bgDark)              \(bigHR[2])\(C.reset)\(C.bgDark)      \(C.cyan)MIN  \(C.cyan + C.bold)\(padLeft(minStr, 3))\(C.reset)\(C.bgDark) \(C.whiteDim)bpm   \(C.chrome)│")
    line("\(C.chrome)│\(C.bgDark)              \(bigHR[3])\(C.reset)\(C.bgDark)                          \(C.chrome)│")
    line("\(C.chrome)│\(C.bgDark)              \(bigHR[4])\(C.reset)\(C.bgDark)      \(C.whiteDim)TIME \(C.white + C.bold)\(pad(durStr, 6))\(C.reset)\(C.bgDark)       \(C.chrome)│")

    // Connection status bar
    line("\(C.chrome)│\(C.bgDark) \(bleStr)\(C.reset)\(C.bgDark)   \(antStr)\(C.reset)\(C.bgDark)                    \(C.whiteDim)SAMPLES \(C.white + C.bold)\(padLeft(sampStr, 6))\(C.reset)\(C.bgDark)       \(C.chrome)│")

    // Divider
    line("\(C.chrome)│\(C.bgDark)\(C.chrome) ─────────────────────────────────────────────────────────────────────────── \(C.chrome)│")

    // HR Zone bar (visual indicator)
    let zoneBar = renderHRZoneBar(hr: hr, width: 60)
    line("\(C.chrome)│\(C.bgDark) \(C.whiteDim)ZONE \(zoneBar)\(C.reset)\(C.bgDark)         \(C.chrome)│")

    // Bottom bezel
    line("\(C.chrome)│\(C.bgDark)\(C.whiteDim)  [R]ecord [S]top [E]xport [A]rnold [V]oice [H]elp [Q]uit               \(C.reset)\(C.bgDark) \(C.chrome)│")
    line("\(C.chrome)└\(String(repeating: "─", count: w - 2))┘\(C.reset)")

    print(output, terminator: "")
}

/// Render a horizontal HR zone bar with the current position marked.
func renderHRZoneBar(hr: Int?, width: Int) -> String {
    // Zones: Rest(<100) | Warm(100-120) | Fat Burn(120-140) | Cardio(140-160) | Peak(160-190+)
    let zones: [(label: String, color: String, maxHR: Int)] = [
        ("REST",    C.greenDim,  100),
        ("WARM",    C.green,     120),
        ("BURN",    C.amber,     140),
        ("CARDIO",  C.red,       160),
        ("PEAK",    C.redBright, 200),
    ]

    let minHR = 50
    let maxHRVal = 200
    let range = maxHRVal - minHR

    // Build the bar
    var bar = ""
    let barWidth = width - 2  // Leave room for brackets
    bar += C.chrome + "["

    for i in 0..<barWidth {
        let hrAtPos = minHR + Int(Double(i) / Double(barWidth) * Double(range))
        let zoneColor = zones.last(where: { hrAtPos < $0.maxHR })?.color ?? C.redBright

        if let currentHR = hr {
            let currentPos = Int(Double(currentHR - minHR) / Double(range) * Double(barWidth))
            let clampedPos = max(0, min(barWidth - 1, currentPos))

            if i == clampedPos {
                bar += C.bold + zoneColor + "▓"
            } else if abs(i - clampedPos) <= 1 {
                bar += zoneColor + "▒"
            } else if i < clampedPos {
                bar += zoneColor + "░"
            } else {
                bar += C.chrome + "·"
            }
        } else {
            bar += C.chrome + "·"
        }
    }

    bar += C.chrome + "]"

    // Add zone label
    if let currentHR = hr {
        let zoneName = zones.last(where: { currentHR < $0.maxHR })?.label ?? "MAX"
        let zoneColor = zones.last(where: { currentHR < $0.maxHR })?.color ?? C.redBright
        bar += " " + zoneColor + C.bold + zoneName
    }

    return bar
}

func printStatus(_ msg: String) {
    print("  \(msg)")
}

// ============================================================================
// MARK: - BLE Callbacks
// ============================================================================

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

// ============================================================================
// MARK: - ANT+ Callbacks
// ============================================================================

antMonitor.onHeartRate = { hr in
    lastANTHR = hr
    recorder.addSample(heartRate: hr, source: .ant)
    if recorder.isRecording { arnold.processHeartRate(hr) }
}

antMonitor.onStatusChange = { msg in
    printStatus(msg)
}

// ============================================================================
// MARK: - Commands
// ============================================================================

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

// ============================================================================
// MARK: - Startup
// ============================================================================

// Clear screen and hide cursor for clean monitor look
print("\u{1B}[2J\u{1B}[H\u{1B}[?25l", terminator: "")

// Show startup splash
print("""
\(C.bgDark)\(C.green)
    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║    \(C.green + C.bold)♥  CARDIAC MONITOR HR-1000A  ♥\(C.reset)\(C.bgDark)\(C.green)                              ║
    ║    \(C.whiteDim)Arnold Schwarzenegger Edition\(C.green)                              ║
    ║                                                               ║
    ║    \(C.whiteDim)Searching for heart rate monitors...\(C.green)                      ║
    ║    \(C.greenDim)• BLE: Wahoo / Bluetooth HR strap\(C.green)                         ║
    ║    \(C.cyanDim)• ANT+: Garmin / ANT+ HR strap (via USB stick)\(C.green)            ║
    ║                                                               ║
    ║    \(C.whiteDim)Type 'h' for help, 'r' to start recording.\(C.green)                ║
    ║                                                               ║
    ╚═══════════════════════════════════════════════════════════════╝
\(C.reset)
""")

// Print initial blank display area
for _ in 0..<displayLines {
    print()
}

// Start monitors
bleMonitor.startScanning()
antMonitor.start()

// Start display refresh timer (faster for smooth waveform animation)
displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
    renderDisplay()
}

// Handle stdin for commands
let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
stdinSource.setEventHandler {
    guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return }

    switch line {
    case "r", "record":
        recorder.startRecording()
        arnold.speakEvent("Let's go! Time to pump that heart! Recording has started!", clipFolder: "start")
        printStatus("Recording started. Press 's' to stop.")
    case "s", "stop":
        recorder.stopRecording()
        arnold.speakEvent("Great workout! You are a champion! Now rest, and come back even stronger!", clipFolder: "stop")
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
        // Show cursor again
        print("\u{1B}[?25h", terminator: "")
        print("\(C.reset)  Goodbye!")
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

// Show audio clip status
printStatus(arnold.clipStatus)
printStatus("Note: If BLE scanning fails, the app needs Bluetooth permission.")

// Run the main run loop
RunLoop.main.run()
