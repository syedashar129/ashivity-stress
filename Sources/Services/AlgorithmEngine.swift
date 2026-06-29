import Foundation
import Combine

/// AlgorithmEngine: converts HRV samples into a normalized 0-100 stress score.
/// This class implements the Z-score mapping described in the project spec.
public final class AlgorithmEngine: ObservableObject {
    public static let shared = AlgorithmEngine()

    @Published public private(set) var currentScore: Double = 50.0
    @Published public private(set) var baselineMean: Double = 0.0
    @Published public private(set) var baselineStd: Double = 1.0

    private init() {}

    /// Compute mean and standard deviation for a list of HRV values.
    public func computeBaseline(from values: [Double]) {
        guard !values.isEmpty else {
            baselineMean = 0
            baselineStd = 1
            return
        }
        let mean = values.reduce(0.0, +) / Double(values.count)
        let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let std = sqrt(max(variance, 1e-6))
        baselineMean = mean
        baselineStd = std
    }

    /// Compute Z-score and map to 0..100 using: score = 50 - (z * 15), clamped.
    public func score(from hrv: Double) -> Double {
        let z = (hrv - baselineMean) / max(baselineStd, 1e-6)
        let mapped = 50.0 - (z * 15.0)
        let clamped = min(max(mapped, 0.0), 100.0)
        return clamped
    }

    /// Update current score from a new HRV sample, optionally applying simple
    /// exponential smoothing to reduce jitter.
    public func update(with hrv: Double, smoothingAlpha: Double = 0.25) {
        let raw = score(from: hrv)
        // simple exponential smoothing
        let smoothed = smoothingAlpha * raw + (1 - smoothingAlpha) * currentScore
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                self.currentScore = smoothed
            }
        }
    }
}
