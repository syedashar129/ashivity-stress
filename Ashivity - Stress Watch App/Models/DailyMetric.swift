//
//  DailyMetric.swift
//  Ashivity - Stress Watch App
//
//  Created by Syed Ashar on 6/29/26.
//

import Foundation

/// Represents aggregated daily stress and energy metrics.
struct DailyMetric: Codable, Identifiable {
    let id: UUID
    let date: Date
    let energyScore: Double  // 0-100
    let avgStress: Double  // Average stress for the day
    let minStress: Double  // Lowest stress recorded
    let maxStress: Double  // Highest stress recorded
    let sampleCount: Int  // Number of measurements
    
    init(
        id: UUID = UUID(),
        date: Date,
        energyScore: Double,
        avgStress: Double,
        minStress: Double,
        maxStress: Double,
        sampleCount: Int = 0
    ) {
        self.id = id
        self.date = date
        self.energyScore = energyScore
        self.avgStress = avgStress
        self.minStress = minStress
        self.maxStress = maxStress
        self.sampleCount = sampleCount
    }
}
