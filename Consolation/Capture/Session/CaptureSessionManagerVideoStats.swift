//
//  CaptureSessionManagerVideoStats.swift
//  Consolation
//

import AVFoundation
import Foundation

extension CaptureSessionManager {
    /// A sample counts toward the low-FPS warning when it delivers more than this many frames below the
    /// configured rate.
    nonisolated static let lowFrameRateShortfallThreshold = 10

    /// Prefer connect-panel selection; device-reported nominal can lag across stop/start.
    func configuredVideoFrameRate(fallbackMeasured: Int) -> Int {
        if let id = selectedVideoDeviceUniqueID,
           let device = AVCaptureDevice(uniqueID: id),
           let eff = CaptureFormatSelector.effectiveFormatForDisplay(device: device, preferences: formatPreferences) {
            return Int(eff.frameRate.rounded())
        }
        if let nominal = nominalVideoFrameRate {
            return Int(nominal.rounded())
        }
        return fallbackMeasured
    }

    /// Next streak value after one stats sample: grows while delivery stays well below the configured rate.
    nonisolated static func nextLowFrameRateSampleStreak(
        current: Int,
        configuredFrameRate: Int,
        deliveredFrames: Int
    ) -> Int {
        configuredFrameRate - deliveredFrames > lowFrameRateShortfallThreshold ? current + 1 : 0
    }

    func receiveVideoFrameRateStats(_ stats: CaptureVideoFrameRateStats) {
        // A sample can land after `stopWatching()`; drop it so a stopped viewer never shows stale stats.
        guard state == .running else { return }
        videoFrameRateStats = stats
        let streak = Self.nextLowFrameRateSampleStreak(
            current: lowFrameRateSampleStreak,
            configuredFrameRate: configuredVideoFrameRate(fallbackMeasured: stats.frames),
            deliveredFrames: stats.frames
        )
        // Only views showing the warning read the streak; skip the write while it holds at zero.
        if streak != lowFrameRateSampleStreak { lowFrameRateSampleStreak = streak }
    }

    func clearVideoFrameRateStats() {
        if videoFrameRateStats != nil { videoFrameRateStats = nil }
        if lowFrameRateSampleStreak != 0 { lowFrameRateSampleStreak = 0 }
    }
}
