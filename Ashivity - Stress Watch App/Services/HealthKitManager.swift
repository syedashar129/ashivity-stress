//
//  HealthKitManager.swift
//  Ashivity - Stress Watch App
//
//  Created by Syed Ashar on 6/29/26.
//

import Foundation
import HealthKit
import Combine

/// Manages HealthKit access, queries, and background observing for HRV and heart rate data.
@MainActor
final class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()
    
    @Published var isAuthorized = false
    @Published var lastHRVSample: Double?
    @Published var lastHeartRate: Double?
    @Published var baselineMean: Double = 0
    @Published var baselineStd: Double = 1
    @Published var hrvSamples: [StressReading] = []
    
    private let healthStore = HKHealthStore()
    private var observers: [HKQuery] = []
    
    // MARK: - Authorization
    
    /// Request HealthKit permissions for HRV, Heart Rate, and Sleep data.
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available on this device")
            return
        }
        
        var readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        
        // HRV is available on iOS 11+ and watchOS 4+
        if #available(watchOS 6.0, iOS 13.0, *) {
            if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                readTypes.insert(hrvType)
            }
        }
        
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleepType)
        }
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthorized = true
                    print("✅ HealthKit authorization granted")
                    // Start background observers
                    self?.startObservingHRV()
                    // Fetch baseline from last 30 days
                    self?.fetchBaseline()
                } else if let error = error {
                    print("❌ HealthKit authorization failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - HRV Observer Query
    
    /// Start a background observer for new HRV samples.
    private func startObservingHRV() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            print("⚠️ HRV type not available on this platform")
            return
        }
        
        let observerQuery = HKObserverQuery(
            sampleType: hrvType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            if let error = error {
                print("❌ Observer query error: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            // New samples arrived; fetch them
            DispatchQueue.main.async {
                self?.fetchLatestHRVSamples()
            }
            
            completionHandler()
        }
        
        healthStore.execute(observerQuery)
        observers.append(observerQuery)
        print("✅ HRV observer started")
    }
    
    // MARK: - Fetch Latest HRV Samples
    
    /// Fetch the most recent HRV samples (last 24 hours).
    private func fetchLatestHRVSamples() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: oneDayAgo, end: now)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            if let error = error {
                print("❌ HRV sample fetch error: \(error.localizedDescription)")
                return
            }
            
            if let hrvSamples = samples as? [HKQuantitySample] {
                DispatchQueue.main.async {
                    self?.processHRVSamples(hrvSamples)
                }
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Process and store HRV samples, compute stress score.
    private func processHRVSamples(_ samples: [HKQuantitySample]) {
        for sample in samples {
            let hrvValue = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            lastHRVSample = hrvValue
            
            // Compute stress score using baseline
            let z = (hrvValue - baselineMean) / max(baselineStd, 1e-6)
            let mapped = 50.0 - (z * 15.0)
            let stressScore = min(max(mapped, 0.0), 100.0)
            
            let reading = StressReading(
                timestamp: sample.startDate,
                hrvValue: hrvValue,
                stressScore: stressScore,
                source: "HealthKit"
            )
            
            // Append to cache (remove older than 24h)
            hrvSamples.append(reading)
            if hrvSamples.count > 200 {
                hrvSamples.removeFirst()
            }
            
            print("📊 HRV: \(String(format: "%.1f", hrvValue))ms, Stress: \(String(format: "%.0f", stressScore))")
        }
    }
    
    // MARK: - Fetch 30-Day Baseline
    
    /// Fetch 30-day HRV baseline for Z-score normalization.
    private func fetchBaseline() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return }
        
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: now)
        
        // Use HKStatisticsCollectionQuery for daily aggregates
        let interval = DateComponents(day: 1)
        
        let query = HKStatisticsCollectionQuery(
            quantityType: hrvType,
            quantitySamplePredicate: predicate,
            options: [.discreteAverage, .discreteMin, .discreteMax],
            anchorDate: thirtyDaysAgo,
            intervalComponents: interval
        )
        
        query.initialResultsHandler = { [weak self] _, collection, error in
            if let error = error {
                print("❌ Baseline fetch error: \(error.localizedDescription)")
                return
            }
            
            guard let collection = collection else { return }
            
            var allHRVValues: [Double] = []
            
            collection.enumerateStatistics(from: thirtyDaysAgo, to: now) { stats, _ in
                if let avg = stats.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli)) {
                    allHRVValues.append(avg)
                }
            }
            
            DispatchQueue.main.async {
                self?.computeBaseline(from: allHRVValues)
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Compute baseline mean and standard deviation from HRV values.
    private func computeBaseline(from values: [Double]) {
        guard !values.isEmpty else {
            print("⚠️ No baseline data available; using defaults")
            baselineMean = 50
            baselineStd = 1
            return
        }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let stddev = sqrt(max(variance, 1e-6))
        
        baselineMean = mean
        baselineStd = stddev
        
        print("📈 Baseline computed: μ=\(String(format: "%.1f", mean))ms, σ=\(String(format: "%.1f", stddev))ms from \(values.count) days")
    }
    
    // MARK: - Heart Rate Query
    
    /// Fetch latest heart rate samples (optional, for Phase 2+).
    func fetchHeartRate() {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        let now = Date()
        let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: oneHourAgo, end: now)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            if let error = error {
                print("❌ HR sample fetch error: \(error.localizedDescription)")
                return
            }
            
            if let hrSamples = samples as? [HKQuantitySample], let latest = hrSamples.first {
                let hr = latest.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                DispatchQueue.main.async {
                    self?.lastHeartRate = hr
                    print("❤️ Heart Rate: \(String(format: "%.0f", hr)) bpm")
                }
            }
        }
        
        healthStore.execute(query)
    }
}
