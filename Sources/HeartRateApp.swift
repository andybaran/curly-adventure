import SwiftUI

@main
struct HeartRateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = HeartRateViewModel()

    var body: some Scene {
        WindowGroup("Heart Rate Recorder") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
                .onAppear { appDelegate.viewModel = viewModel }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.cleanup()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            // Remove "New Window" from File menu (single-window app)
            CommandGroup(replacing: .newItem) { }

            // Standard Help menu
            CommandGroup(replacing: .help) {
                Button("Heart Rate Recorder Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/andybaran/curly-adventure")!)
                }
            }

            // App-specific menus
            CommandMenu("Recording") {
                Button("Start Recording") { viewModel.startRecording() }
                    .keyboardShortcut("r")
                    .disabled(viewModel.isRecording)
                Button("Stop Recording") { viewModel.stopRecording() }
                    .keyboardShortcut(".")
                    .disabled(!viewModel.isRecording)
                Divider()
                Button("Export to FIT") { viewModel.exportFIT() }
                    .keyboardShortcut("e")
                    .disabled(viewModel.sampleCount == 0)
            }
            CommandMenu("Coach") {
                Button(viewModel.arnoldEnabled ? "Disable Arnold" : "Enable Arnold") {
                    viewModel.toggleArnold()
                }
                .keyboardShortcut("k")
                Button(viewModel.arnoldMuted ? "Unmute Voice" : "Mute Voice") {
                    viewModel.toggleMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Cycle Voice (\(viewModel.voiceName))") {
                    viewModel.cycleVoice()
                }
                .keyboardShortcut("j")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var viewModel: HeartRateViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable full-screen support on all windows
        for window in NSApplication.shared.windows {
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.title = "Heart Rate Recorder"
        }

        // Also observe for any future windows
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.collectionBehavior.insert(.fullScreenPrimary)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.cleanup()
    }
}
