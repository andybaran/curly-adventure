# Heart Rate Recorder

A macOS command-line tool that connects to **Bluetooth LE** and **ANT+** heart rate monitors simultaneously, displays real-time heart rate data, and exports recordings to **.FIT** format for upload to **Garmin Connect**.

## Hardware Support

| Monitor | Protocol | Connection |
|---------|----------|------------|
| Wahoo TICKR / any BLE HR strap | Bluetooth LE | Built-in Mac Bluetooth |
| Garmin / any ANT+ HR strap | ANT+ | USB ANT+ stick (e.g., Garmin USB-m) |

## Requirements

- macOS 13+ (Ventura or later)
- Apple Silicon (M1/M2/M3) or Intel Mac
- Xcode Command Line Tools (`xcode-select --install`)
- For ANT+: A USB ANT+ adapter plugged in

## Build

```bash
swift build -c release
```

The binary will be at `.build/release/HeartRateRecorder`.

## Run

```bash
.build/release/HeartRateRecorder
```

On first run, macOS will prompt for Bluetooth permission — grant it.

## Usage

Once running, the app scans for both BLE and ANT+ heart rate monitors automatically.

### Commands

| Command | Action |
|---------|--------|
| `r` / `record` | Start recording heart rate data |
| `s` / `stop` | Stop recording |
| `e` / `export` | Export recording to .FIT file |
| `q` / `quit` | Stop, auto-export if data exists, and exit |
| `h` / `help` | Show help |

### Workflow

1. Launch the app
2. Put on your heart rate strap and make sure it's active (wet the sensor pads)
3. Wait for the monitor to connect (you'll see the status update)
4. Type `r` to start recording
5. Do your workout
6. Type `s` to stop recording
7. Type `e` to export (or just `q` — it auto-exports on quit)

### Uploading to Garmin Connect

1. Go to [Garmin Connect Import](https://connect.garmin.com/modern/import-data)
2. Click **Import Data** and select the `.fit` file from your Downloads folder
3. The activity will appear in your Garmin Connect timeline with full HR data

## File Structure

```
Sources/
  main.swift                 - Entry point, terminal UI, command handling
  BLEHeartRateMonitor.swift  - CoreBluetooth BLE HR monitor connection
  ANTHeartRateMonitor.swift  - IOKit USB ANT+ stick communication
  HeartRateRecorder.swift    - HR data storage and statistics
  FITExporter.swift          - Garmin .FIT file format writer
  Info.plist                 - Bluetooth permission description
HeartRateRecorder.entitlements - App entitlements for Bluetooth + USB
```

## Troubleshooting

**BLE monitor not found:**
- Make sure the strap is wet/active and in range
- Check System Settings > Privacy & Security > Bluetooth — ensure Terminal has access
- Try resetting Bluetooth: Option-click the Bluetooth menu bar icon > Reset

**ANT+ stick not detected:**
- Unplug and replug the USB ANT+ adapter
- Check System Information > USB to verify the stick appears
- The stick should show as vendor `0x0FCF` (Dynastream/Garmin)

**Permission denied errors:**
- Run `codesign --entitlements HeartRateRecorder.entitlements -s - .build/release/HeartRateRecorder` to sign with entitlements
