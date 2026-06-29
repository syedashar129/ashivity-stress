import Foundation

/// Simple model for a stress reading. This is a Codable/Identifiable struct used
/// for Phase 1. The plan is to migrate this to SwiftData `@Model` later.
public struct StressReading: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let hrv: Double
    public let heartRate: Double?
    public let stressScore: Double
    public let source: String?

    public init(id: UUID = .init(), timestamp: Date = Date(), hrv: Double, heartRate: Double? = nil, stressScore: Double, source: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.hrv = hrv
        self.heartRate = heartRate
        self.stressScore = stressScore
        self.source = source
    }
}
