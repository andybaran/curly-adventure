import SwiftUI

// MARK: - Color Theme

extension Color {
    static let ecgGreen = Color(red: 0, green: 1, blue: 0.255)       // #00FF41
    static let monitorBg = Color(red: 0.04, green: 0.04, blue: 0.055)
    static let panelBg = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let dimGreen = Color(red: 0, green: 0.4, blue: 0.1)
    static let gridLine = Color(red: 0.08, green: 0.12, blue: 0.08)
}

// MARK: - Main View

struct ContentView: View {
    @EnvironmentObject var vm: HeartRateViewModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                headerBar
                Divider().overlay(Color.ecgGreen.opacity(0.2))

                ECGWaveformView(heartRate: vm.currentHR)
                    .frame(height: max(geo.size.height * 0.28, 160))

                Divider().overlay(Color.ecgGreen.opacity(0.2))

                vitalsSection
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)

                zoneBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                statusSection
                    .padding(.horizontal, 20)
                    .layoutPriority(1)

                Divider().overlay(Color.ecgGreen.opacity(0.2))

                controlBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .background(Color.monitorBg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
                .font(.title3)
            Text("Heart Rate Recorder")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            connectionBadge("BLE", connected: vm.isBLEConnected)
            connectionBadge("ANT+", connected: vm.isANTConnected)

            if vm.isRecording {
                recordingBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.panelBg)
    }

    private var recordingBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .modifier(PulseEffect())
            Text("REC")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.12))
        .cornerRadius(4)
    }

    private func connectionBadge(_ label: String, connected: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? Color.green : Color.gray.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(connected ? .green : .gray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((connected ? Color.green : Color.gray).opacity(0.08))
        .cornerRadius(4)
    }

    // MARK: - Vitals

    private var vitalsSection: some View {
        HStack(spacing: 24) {
            // Big HR number
            VStack(spacing: 2) {
                Text(vm.currentHR > 0 ? "\(vm.currentHR)" : "--")
                    .font(.system(size: 110, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.currentHR > 0 ? Color.ecgGreen : .gray.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("BPM")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.ecgGreen.opacity(0.5))

                Text(vm.currentZone.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(vm.currentZone.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(vm.currentZone.color.opacity(0.15))
                    .cornerRadius(4)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

            // Stats panel
            VStack(alignment: .leading, spacing: 0) {
                statsHeader
                Divider().overlay(Color.ecgGreen.opacity(0.15)).padding(.vertical, 6)
                statRow(icon: "heart", label: "AVG", value: vm.averageHR > 0 ? "\(vm.averageHR)" : "--", unit: "BPM", color: .cyan)
                statRow(icon: "arrow.up", label: "MAX", value: vm.maxHR > 0 ? "\(vm.maxHR)" : "--", unit: "BPM", color: .red)
                statRow(icon: "arrow.down", label: "MIN", value: vm.minHR > 0 ? "\(vm.minHR)" : "--", unit: "BPM", color: .blue)
                Divider().overlay(Color.ecgGreen.opacity(0.15)).padding(.vertical, 6)
                statRow(icon: "clock", label: "TIME", value: formatDuration(vm.duration), unit: "", color: .white)
                statRow(icon: "waveform.path", label: "SAMPLES", value: formatNumber(vm.sampleCount), unit: "", color: .white)
            }
            .padding(16)
            .background(Color.panelBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.ecgGreen.opacity(0.1), lineWidth: 1)
            )
            .frame(maxWidth: 300)
        }
    }

    private var statsHeader: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(Color.ecgGreen.opacity(0.5))
                .font(.caption)
            Text("SESSION STATS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color.ecgGreen.opacity(0.5))
            Spacer()
            if vm.isRecording {
                Text(formatDuration(vm.duration))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }

    private func statRow(icon: String, label: String, value: String, unit: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color.opacity(0.6))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 65, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 30, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Zone Bar

    private var zoneBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(HeartRateViewModel.HRZone.allCases, id: \.self) { zone in
                            zoneSegment(zone, totalWidth: geo.size.width)
                        }
                    }
                    .cornerRadius(4)

                    if vm.currentHR > 0 {
                        let frac = HeartRateViewModel.HRZone.fraction(hr: vm.currentHR)
                        let pos = frac * geo.size.width
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(.white)
                                .frame(width: 3, height: 22)
                                .shadow(color: .white.opacity(0.5), radius: 4)
                        }
                        .offset(x: pos - 1.5)
                        .animation(.easeInOut(duration: 0.3), value: vm.currentHR)
                    }
                }
            }
            .frame(height: 24)
        }
    }

    private func zoneSegment(_ zone: HeartRateViewModel.HRZone, totalWidth: CGFloat) -> some View {
        let widths: [HeartRateViewModel.HRZone: CGFloat] = [
            .rest: 60, .warmUp: 20, .fatBurn: 20, .cardio: 20, .peak: 30, .max: 30
        ]
        let totalUnits: CGFloat = 180
        let width = (widths[zone] ?? 20) / totalUnits * totalWidth

        return ZStack {
            Rectangle().fill(zone.color.opacity(vm.currentZone == zone ? 0.45 : 0.2))
            Text(zone.rawValue)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(zone.color.opacity(vm.currentZone == zone ? 1 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(width: width)
    }

    // MARK: - Status

    private var statusSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(vm.statusMessages) { msg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(timeString(msg.timestamp))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.6))
                            Text(msg.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color.ecgGreen.opacity(0.7))
                        }
                        .id(msg.id)
                    }
                }
                .padding(8)
            }
            .frame(minHeight: 60, maxHeight: 120)
            .background(Color.black.opacity(0.3))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.ecgGreen.opacity(0.08), lineWidth: 1)
            )
            .onChange(of: vm.statusMessages.count) { _ in
                if let last = vm.statusMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 10) {
            if !vm.isRecording {
                actionButton("Record", icon: "record.circle", color: .red) {
                    vm.startRecording()
                }
            } else {
                actionButton("Stop", icon: "stop.circle.fill", color: .orange) {
                    vm.stopRecording()
                }
            }

            actionButton("Export", icon: "square.and.arrow.up", color: .blue) {
                vm.exportFIT()
            }
            .disabled(vm.sampleCount == 0)
            .opacity(vm.sampleCount == 0 ? 0.4 : 1)

            Spacer()

            actionButton(
                vm.arnoldEnabled ? "Arnold: ON" : "Arnold: OFF",
                icon: "figure.strengthtraining.traditional",
                color: vm.arnoldEnabled ? .green : .gray
            ) {
                vm.toggleArnold()
            }

            actionButton(
                vm.arnoldMuted ? "Unmuted" : "Muted",
                icon: vm.arnoldMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                color: vm.arnoldMuted ? .gray : .green
            ) {
                vm.toggleMute()
            }

            actionButton(
                vm.voiceName,
                icon: "person.wave.2",
                color: .cyan
            ) {
                vm.cycleVoice()
            }
        }
    }

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formatNumber(_ n: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }
}

// MARK: - Pulse Animation

struct PulseEffect: ViewModifier {
    @State private var animating = false

    func body(content: Content) -> some View {
        content
            .opacity(animating ? 0.2 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
    }
}
