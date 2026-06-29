import SwiftUI

import Combine

/// Minimal DashboardView for Phase 1. Shows a circular energy gauge and the
/// current computed stress score. This is a placeholder UI to wire up the
/// AlgorithmEngine and HealthKitManager.
public struct DashboardView: View {
    @StateObject private var engine = AlgorithmEngine.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Animated circular ring using TimelineView and AngularGradient
            TimelineView(.animation) { timeline in
                let angle = Angle(degrees: (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4)) * 90)
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 18)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: CGFloat(engine.currentScore / 100.0))
                        .rotation(Angle(degrees: -90))
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [.blue, .green, .yellow, .red]), center: .center, startAngle: .zero, endAngle: angle),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)

                    VStack {
                        Text(String(format: "%.0f", engine.currentScore))
                            .font(.title)
                            .bold()
                        Text("Stress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }

            // Quick controls for Phase 1: simulate a new HRV sample
            HStack(spacing: 12) {
                Button("Sim Low") {
                    engine.update(with: 100) // high HRV -> low stress
                }
                .buttonStyle(.bordered)

                Button("Sim High") {
                    engine.update(with: 10) // low HRV -> high stress
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }
}

// Preview for Xcode canvas
#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
#endif
