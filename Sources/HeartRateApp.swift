import SwiftUI

@main
struct HeartRateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = HeartRateViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear { appDelegate.viewModel = viewModel }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.cleanup()
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) { }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.cleanup()
    }
}
