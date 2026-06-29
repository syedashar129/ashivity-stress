//
//  StressReading.swift
//  Ashivity - Stress Watch App
//
//  Created by Syed Ashar on 6/29/26.
//

import Foundation

/// Represents a single stress measurement with HRV, heart rate, and computed stress score.
struct StressReading: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let hrvValue: Double  // HRV (SDNN) in milliseconds
    let heartRate: Double?  // Optional heart rate in bpm
    let stressScore: Double  // Computed 0-100 stress score
    let source: String  // "HealthKit" or "Manual"
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        hrvValue: Double,
        heartRate: Double? = nil,
        stressScore: Double,
        source: String = "HealthKit"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hrvValue = hrvValue
        self.heartRate = heartRate
        self.stressScore = stressScore
        self.source = source
    }
}
