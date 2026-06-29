import Foundation

/// Daily aggregate metrics for quick dashboard rendering. Codable for Phase 1.
public struct DailyMetric: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public var energyScore: Double
    public var avgStress: Double
    public var minStress: Double
    public var maxStress: Double

    public init(id: UUID = .init(), date: Date = Date(), energyScore: Double = 50, avgStress: Double = 50, minStress: Double = 50, maxStress: Double = 50) {
        self.id = id
        self.date = date
        self.energyScore = energyScore
        self.avgStress = avgStress
        self.minStress = minStress
        self.maxStress = maxStress
    }
}
