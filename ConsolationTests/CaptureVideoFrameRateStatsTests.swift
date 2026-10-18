//
//  CaptureVideoFrameRateStatsTests.swift
//  ConsolationTests
//

import Observation
import Synchronization
import Testing
@testable import Consolation

struct CaptureVideoFrameRateStatsTests {
    private static func stats(frames: Int) -> CaptureVideoFrameRateStats {
        CaptureVideoFrameRateStats(
            wallFPS: Double(frames),
            presentationFPS: Double(frames),
            frames: frames,
            droppedFrames: 0,
            maxPresentationGap: 0.05
        )
    }

    @Test func lowFrameRateStreakGrowsWhileDeliveryStaysWellBelowConfiguredRate() {
        var streak = 0
        for _ in 0..<3 {
            streak = CaptureSessionManager.nextLowFrameRateSampleStreak(
                current: streak,
                configuredFrameRate: 60,
                deliveredFrames: 30
            )
        }
        #expect(streak == 3)
    }

    @Test func lowFrameRateStreakResetsWhenDeliveryRecovers() {
        let streak = CaptureSessionManager.nextLowFrameRateSampleStreak(
            current: 4,
            configuredFrameRate: 60,
            deliveredFrames: 59
        )
        #expect(streak == 0)
    }

    @Test func shortfallAtTheThresholdDoesNotCount() {
        let threshold = CaptureSessionManager.lowFrameRateShortfallThreshold
        let atThreshold = CaptureSessionManager.nextLowFrameRateSampleStreak(
            current: 2,
            configuredFrameRate: 60,
            deliveredFrames: 60 - threshold
        )
        let pastThreshold = CaptureSessionManager.nextLowFrameRateSampleStreak(
            current: 2,
            configuredFrameRate: 60,
            deliveredFrames: 60 - threshold - 1
        )
        #expect(atThreshold == 0)
        #expect(pastThreshold == 3)
    }

    @Test func statsAreKeptOnlyWhileRunningAndClearedWhenStopped() {
        let capture = CaptureSessionManager(formatPreferences: .defaultForLaunch)

        capture.receiveVideoFrameRateStats(Self.stats(frames: 30))
        #expect(capture.videoFrameRateStats == nil)

        capture.state = .running
        capture.receiveVideoFrameRateStats(Self.stats(frames: 30))
        #expect(capture.videoFrameRateStats == Self.stats(frames: 30))

        capture.state = .idle
        #expect(capture.videoFrameRateStats == nil)
        #expect(capture.lowFrameRateSampleStreak == 0)
    }

    @Test func newStatsNotifyObservers() {
        let capture = CaptureSessionManager(formatPreferences: .defaultForLaunch)
        capture.state = .running
        let changed = Mutex(false)
        withObservationTracking {
            _ = capture.videoFrameRateStats
        } onChange: {
            changed.withLock { $0 = true }
        }

        capture.receiveVideoFrameRateStats(Self.stats(frames: 60))

        #expect(changed.withLock { $0 })
    }
}
