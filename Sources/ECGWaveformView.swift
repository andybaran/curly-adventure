import SwiftUI

/// Animated ECG waveform that generates a realistic PQRST cardiac trace.
/// Uses TimelineView for smooth 60fps animation and Canvas for efficient rendering.
struct ECGWaveformView: View {
    let heartRate: Int

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                drawGrid(context: context, size: size)
                drawTrace(context: context, size: size, time: now)
                drawLabels(context: context, size: size)
            }
        }
        .background(Color.monitorBg)
    }

    // MARK: - Grid

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 20
        let color = Color.gridLine

        // Minor grid
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(path, with: .color(color), lineWidth: 0.5)

        // Major grid (every 5 cells)
        var majorPath = Path()
        x = 0
        while x <= size.width {
            majorPath.move(to: CGPoint(x: x, y: 0))
            majorPath.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing * 5
        }
        y = 0
        while y <= size.height {
            majorPath.move(to: CGPoint(x: 0, y: y))
            majorPath.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing * 5
        }
        context.stroke(majorPath, with: .color(color.opacity(1.8)), lineWidth: 0.8)

        // Center baseline
        let centerY = size.height / 2
        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: centerY))
        baseline.addLine(to: CGPoint(x: size.width, y: centerY))
        context.stroke(baseline, with: .color(Color.dimGreen.opacity(0.3)), lineWidth: 0.5)
    }

    // MARK: - Trace

    private func drawTrace(context: GraphicsContext, size: CGSize, time: Double) {
        let pointCount = Int(size.width / 1.5) // ~1 point per 1.5px for smoothness
        guard pointCount > 1 else { return }

        let pixelsPerSecond: Double = 150
        let centerY = size.height / 2
        let amplitude = size.height * 0.35
        let step = size.width / CGFloat(pointCount - 1)

        var path = Path()

        for i in 0..<pointCount {
            let x = CGFloat(i) * step
            let t = time - Double(pointCount - 1 - i) / pixelsPerSecond * 1.5
            let y: CGFloat

            if heartRate > 0 {
                let bpm = max(Double(heartRate), 30)
                let cycleLen = 60.0 / bpm
                var phase = (t / cycleLen).truncatingRemainder(dividingBy: 1.0)
                if phase < 0 { phase += 1.0 }
                let value = pqrstValue(phase: phase)
                // Add subtle baseline noise
                let noise = CGFloat.random(in: -0.005...0.005)
                y = centerY - (value + noise) * amplitude
            } else {
                // Flat line with tiny noise
                let noise = CGFloat.random(in: -0.003...0.003)
                y = centerY - noise * amplitude
            }

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        // Glow layers (wider, dimmer → narrower, brighter)
        context.stroke(path, with: .color(Color.ecgGreen.opacity(0.08)), lineWidth: 8)
        context.stroke(path, with: .color(Color.ecgGreen.opacity(0.15)), lineWidth: 4)
        context.stroke(path, with: .color(Color.ecgGreen.opacity(0.4)), lineWidth: 2)
        // Sharp trace
        context.stroke(path, with: .color(Color.ecgGreen), lineWidth: 1.2)
    }

    // MARK: - Labels

    private func drawLabels(context: GraphicsContext, size: CGSize) {
        context.draw(
            Text("LEAD II")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color.ecgGreen.opacity(0.35)),
            at: CGPoint(x: 36, y: 14)
        )

        if heartRate > 0 {
            context.draw(
                Text("25mm/s")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.ecgGreen.opacity(0.25)),
                at: CGPoint(x: size.width - 30, y: 14)
            )
        }
    }

    // MARK: - PQRST Waveform Generator

    /// Returns a normalized value (-0.2 to 1.0) for a given phase (0-1) in one cardiac cycle.
    private func pqrstValue(phase: Double) -> CGFloat {
        let p = phase

        // P wave — small atrial depolarization
        if p >= 0.06 && p < 0.18 {
            let t = (p - 0.06) / 0.12
            return CGFloat(0.12 * sin(t * .pi))
        }
        // PR segment (isoelectric)
        if p >= 0.18 && p < 0.26 {
            return 0
        }
        // Q dip
        if p >= 0.26 && p < 0.30 {
            let t = (p - 0.26) / 0.04
            return CGFloat(-0.08 * sin(t * .pi))
        }
        // R peak — sharp ventricular depolarization
        if p >= 0.30 && p < 0.37 {
            let t = (p - 0.30) / 0.07
            return CGFloat(1.0 * sin(t * .pi))
        }
        // S dip
        if p >= 0.37 && p < 0.41 {
            let t = (p - 0.37) / 0.04
            return CGFloat(-0.18 * sin(t * .pi))
        }
        // ST segment
        if p >= 0.41 && p < 0.48 {
            return 0
        }
        // T wave — ventricular repolarization
        if p >= 0.48 && p < 0.64 {
            let t = (p - 0.48) / 0.16
            return CGFloat(0.28 * sin(t * .pi))
        }
        // Baseline
        return 0
    }
}
