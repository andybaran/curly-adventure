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
| `a` / `arnold` | Toggle Arnold Schwarzenegger voice coach on/off |
| `v` / `voice` | Cycle through available TTS voices |
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
  ArnoldCoach.swift          - Arnold Schwarzenegger voice coach (TTS + quotes)
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

## Arnold Voice Coach

The app includes a motivational voice coach that plays audio clips or reads Arnold-style quotes aloud based on your heart rate zone.

### Audio Clips (Recommended)

For the best experience, add your own Arnold audio clips. Run the setup script to create the folder structure:

```bash
./setup-clips.sh
```

This creates `~/HeartRateRecorder/clips/` with subfolders:

| Folder | When it plays |
|--------|---------------|
| `warmup/` | HR < 60% of max |
| `easy/` | HR 60-70% |
| `moderate/` | HR 70-80% |
| `hard/` | HR 80-90% |
| `max/` | HR > 90% |
| `start/` | When you press Record |
| `stop/` | When you press Stop |
| `zone_change/` | When HR crosses a zone boundary |

Drop `.mp3`, `.wav`, or `.m4a` files into each folder. Multiple files per folder are supported — one is picked at random each time. Empty folders fall back to TTS.

**Where to get Arnold clips:**
- Record yourself doing impressions
- Get a personalized [Cameo](https://www.cameo.com) from Arnold himself
- Use an AI voice tool (ElevenLabs, etc.) to generate custom lines
- Save clips from a licensed soundboard app

### TTS Fallback

When no audio clips are available, the app falls back to macOS text-to-speech:

- Press `v` to cycle through voices: Alex, Daniel, Fred, Ralph, Rishi
- Press `a` to toggle the voice coach on/off
- The "Alex" voice at 160 WPM gives the most dramatic effect

**Tip:** Install enhanced voices in System Settings > Accessibility > Spoken Content > System Voice > Manage Voices for better quality.
