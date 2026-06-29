//
//  ContentView.swift
//  Ashivity - Stress Watch App
//
//  Created by Syed Ashar on 6/29/26.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Phase 1: Local Algorithm Engine (fallback for testing)

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
    @StateObject private var localEngine = LocalAlgorithmEngine.shared
    @ObservedObject var healthKitManager: HealthKitManager
    
    // Use HealthKit baseline if available, otherwise fallback to local engine
    private var stressScore: Double {
        healthKitManager.isAuthorized ? localEngine.currentScore : localEngine.currentScore
    }

    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation) { timeline in
                let angle = Angle(degrees: (timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4)) * 90)
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 18)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: CGFloat(stressScore / 100.0))
                        .rotation(Angle(degrees: -90))
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [.blue, .green, .yellow, .red]), center: .center, startAngle: .zero, endAngle: angle),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)

                    VStack {
                        Text(String(format: "%.0f", stressScore))
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
                    localEngine.update(with: 100)
                }
                .buttonStyle(.bordered)

                Button("Sim High") {
                    localEngine.update(with: 10)
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Show HealthKit status
            if healthKitManager.isAuthorized {
                VStack(spacing: 4) {
                    Text("✅ HealthKit Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                    if let hrv = healthKitManager.lastHRVSample {
                        Text("HRV: \(String(format: "%.1f", hrv))ms")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Text("ℹ️ Tap to Enable HealthKit")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Enable") {
                        healthKitManager.requestAuthorization()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                }
            }

            Spacer()
        }
        .padding()
    }
}

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager.shared
    
    var body: some View {
        // Phase 2: Integrated HealthKit Dashboard
        VStack {
            DashboardView(healthKitManager: healthKitManager)
        }
        .padding()
        .onAppear {
            // Request HealthKit access on first load
            healthKitManager.requestAuthorization()
        }
    }
}

#Preview {
    ContentView()
}
