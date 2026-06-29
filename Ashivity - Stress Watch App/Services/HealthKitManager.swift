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
    @Published var errorMessage: String?
    @Published var isProcessing = false
    
    private let healthStore = HKHealthStore()
    private var observers: [HKQuery] = []
    private var baselineComputed = false
    
    // MARK: - Authorization
    
    /// Request HealthKit permissions for HRV, Heart Rate, and Sleep data.
    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit is not available on this device"
            print("❌ HealthKit not available on this device")
            return
        }
        
        var readTypes: Set<HKObjectType> = []
        
        // Heart Rate (always available)
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(hrType)
        } else {
            errorMessage = "Heart Rate type not available"
            print("⚠️ Heart Rate type not available")
        }
        
        // HRV is available on iOS 13+ and watchOS 6+
        if #available(watchOS 6.0, iOS 13.0, *) {
            if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
                readTypes.insert(hrvType)
            } else {
                errorMessage = "HRV type not available on this platform"
                print("⚠️ HRV type not available")
            }
        } else {
            errorMessage = "HRV requires watchOS 6+ or iOS 13+"
            print("⚠️ HRV requires watchOS 6+ or iOS 13+")
        }
        
        // Sleep (optional)
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleepType)
        }
        
        guard !readTypes.isEmpty else {
            errorMessage = "No HealthKit types available to request"
            print("❌ No HealthKit types available")
            return
        }
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthorized = true
                    self?.errorMessage = nil
                    print("✅ HealthKit authorization granted")
                    // Start background observers
                    self?.startObservingHRV()
                    // Fetch baseline from last 30 days
                    self?.fetchBaseline()
                } else if let error = error {
                    self?.errorMessage = "HealthKit auth failed: \(error.localizedDescription)"
                    print("❌ HealthKit authorization failed: \(error.localizedDescription)")
                } else {
                    self?.errorMessage = "HealthKit authorization denied"
                    print("❌ HealthKit authorization denied by user")
                }
            }
        }
    }
    
    // MARK: - HRV Observer Query
    
    /// Start a background observer for new HRV samples.
    private func startObservingHRV() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            errorMessage = "HRV type unavailable for observer"
            print("⚠️ HRV type not available for observer")
            return
        }
        
        let observerQuery = HKObserverQuery(
            sampleType: hrvType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            
            if let error = error {
                print("⚠️ Observer query error: \(error.localizedDescription)")
                return
            }
            
            print("🔔 HRV observer notified of new samples")
            // New samples arrived; fetch them
            DispatchQueue.main.async {
                self?.fetchLatestHRVSamples()
            }
        }
        
        healthStore.execute(observerQuery)
        observers.append(observerQuery)
        print("✅ HRV observer started successfully")
    }
    
    // MARK: - Fetch Latest HRV Samples
    
    /// Fetch the most recent HRV samples (last 24 hours).
    private func fetchLatestHRVSamples() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            print("⚠️ HRV type unavailable for sample fetch")
            return
        }
        
        guard isAuthorized else {
            print("⚠️ Not authorized to fetch HRV samples")
            return
        }
        
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let predicate = HKQuery.predicateForSamples(withStart: oneDayAgo, end: now)
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: predicate,
            limit: 100,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to fetch HRV samples: \(error.localizedDescription)"
                }
                print("⚠️ HRV sample fetch error: \(error.localizedDescription)")
                return
            }
            
            guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                print("ℹ️ No new HRV samples available")
                return
            }
            
            print("📥 Fetched \(hrvSamples.count) HRV samples")
            
            DispatchQueue.main.async {
                self?.processHRVSamples(hrvSamples)
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Process and store HRV samples, compute stress score.
    private func processHRVSamples(_ samples: [HKQuantitySample]) {
        guard !samples.isEmpty else { return }
        
        // Track processed timestamps to avoid duplicates
        let existingTimestamps = Set(hrvSamples.map { $0.timestamp })
        
        var newSamplesCount = 0
        
        for sample in samples {
            // Skip if we already have this sample
            if existingTimestamps.contains(sample.startDate) {
                continue
            }
            
            // Extract HRV value in milliseconds
            let hrvValue = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            
            // Validate HRV value is reasonable (typically 0-500ms range)
            guard hrvValue > 0 && hrvValue < 500 else {
                print("⚠️ Skipping invalid HRV value: \(hrvValue)ms")
                continue
            }
            
            lastHRVSample = hrvValue
            
            // Compute stress score using baseline
            let z = (hrvValue - baselineMean) / max(baselineStd, 1e-6)
            let mapped = 50.0 - (z * 15.0)
            let stressScore = min(max(mapped, 0.0), 100.0)
            
            // Create StressReading using the Watch App model initializer
            let reading = StressReading(
                timestamp: sample.startDate,
                hrvValue: hrvValue,
                heartRate: nil,
                stressScore: stressScore,
                source: "HealthKit"
            )

            // Append to cache
            hrvSamples.append(reading)
            newSamplesCount += 1

            print("📊 HRV: \(String(format: "%.1f", hrvValue))ms, Stress: \(String(format: "%.0f", stressScore))")
        }
        
        // Keep only last 200 samples (24-48 hours of data)
        if hrvSamples.count > 200 {
            hrvSamples = Array(hrvSamples.suffix(200))
        }
        
        if newSamplesCount > 0 {
            print("✅ Processed \(newSamplesCount) new HRV samples")
            errorMessage = nil
        }
    }
    
    // MARK: - Fetch 30-Day Baseline
    
    /// Fetch 30-day HRV baseline for Z-score normalization.
    private func fetchBaseline() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            errorMessage = "HRV type unavailable for baseline"
            print("⚠️ HRV type unavailable for baseline computation")
            return
        }
        
        guard isAuthorized else {
            print("⚠️ Not authorized to fetch baseline")
            return
        }
        
        guard !baselineComputed else {
            print("ℹ️ Baseline already computed, skipping re-fetch")
            return
        }
        
        isProcessing = true
        
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
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
            DispatchQueue.main.async {
                if let error = error {
                    self?.errorMessage = "Baseline fetch failed: \(error.localizedDescription)"
                    self?.isProcessing = false
                    print("⚠️ Baseline fetch error: \(error.localizedDescription)")
                    return
                }
                
                guard let collection = collection else {
                    self?.errorMessage = "No baseline collection data"
                    self?.isProcessing = false
                    print("⚠️ No baseline collection returned")
                    return
                }
                
                var allHRVValues: [Double] = []
                
                collection.enumerateStatistics(from: thirtyDaysAgo, to: now) { stats, _ in
                    if let avg = stats.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli)) {
                        // Validate value is reasonable
                        if avg > 0 && avg < 500 {
                            allHRVValues.append(avg)
                        }
                    }
                }
                
                self?.computeBaseline(from: allHRVValues)
                self?.isProcessing = false
            }
        }
        
        healthStore.execute(query)
    }
    
    /// Compute baseline mean and standard deviation from HRV values.
    private func computeBaseline(from values: [Double]) {
        // Use defaults if insufficient data
        if values.isEmpty {
            print("⚠️ No baseline data available (0 days); using population defaults")
            baselineMean = 50.0  // Population average HRV ~50ms
            baselineStd = 20.0   // Population stddev ~20ms
            baselineComputed = true
            errorMessage = "Using default baseline (no user data yet)"
            return
        }
        
        // Warn if very limited data
        if values.count < 7 {
            print("⚠️ Limited baseline data (\(values.count) days); baseline may be inaccurate")
            errorMessage = "Limited data: \(values.count) days (awaiting 7+ days)"
        }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        let stddev = sqrt(max(variance, 1e-6))
        
        // Validate computed values
        guard mean > 0, stddev > 0 else {
            print("❌ Invalid baseline computation: μ=\(mean), σ=\(stddev)")
            baselineMean = 50.0
            baselineStd = 20.0
            baselineComputed = true
            errorMessage = "Baseline computation failed; using defaults"
            return
        }
        
        baselineMean = mean
        baselineStd = stddev
        baselineComputed = true
        
        print("✅ Baseline computed: μ=\(String(format: "%.1f", mean))ms, σ=\(String(format: "%.1f", stddev))ms from \(values.count) days")
        
        if values.count >= 7 {
            errorMessage = nil  // Clear error if we have sufficient data
        }
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
 
