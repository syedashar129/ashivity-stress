//
//  ContentView.swift
//  Ashivity - Stress Watch App
//
//  Created by Syed Ashar on 6/29/26.
//

import SwiftUI
import Foundation
import Combine

/// Local lightweight AlgorithmEngine used by the watch target in Phase 1.
@MainActor
final class LocalAlgorithmEngine: ObservableObject {
    static let shared = LocalAlgorithmEngine()
    @Published private(set) var currentScore: Double = 50
    @Published private(set) var baselineMean: Double = 0
    @Published private(set) var baselineStd: Double = 1

    private init() {}

    func computeBaseline(from values: [Double]) {
        guard !values.isEmpty else { baselineMean = 0; baselineStd = 1; return }
        let mean = values.reduce(0.0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        baselineMean = mean
        baselineStd = sqrt(max(variance, 1e-6))
    }

    func score(from hrv: Double) -> Double {
        let z = (hrv - baselineMean) / max(baselineStd, 1e-6)
        let mapped = 50.0 - (z * 15.0)
        return min(max(mapped, 0.0), 100.0)
    }

    func update(with hrv: Double, smoothingAlpha: Double = 0.25) {
        let raw = score(from: hrv)
        let smoothed = smoothingAlpha * raw + (1 - smoothingAlpha) * currentScore
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            currentScore = smoothed
        }
    }
}

struct DashboardView: View {
    @StateObject private var engine = LocalAlgorithmEngine.shared

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                let angle = Angle(degrees: (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4)) * 90)
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 18)
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

            HStack(spacing: 12) {
                Button("Sim Low") {
                    engine.update(with: 100)
                }
                .buttonStyle(.bordered)

                Button("Sim High") {
                    engine.update(with: 10)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }
}

struct ContentView: View {
    var body: some View {
        // Phase 1: show the dashboard placeholder
        VStack {
            DashboardView()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
