import AVFoundation
import Foundation

private enum CaptureVideoFormatUserDefaultsKeys {
    nonisolated static let minimumFrameRateKey = AppIdentifier.scoped("captureVideoMinimumFrameRate")
    nonisolated static let preferredWidthKey = AppIdentifier.scoped("captureVideoPreferredWidth")
    nonisolated static let preferredHeightKey = AppIdentifier.scoped("captureVideoPreferredHeight")
    nonisolated static let preferredFrameRateKey = AppIdentifier.scoped("captureVideoPreferredFrameRate")
}

struct CaptureVideoFormatPreferences: Sendable, Equatable {
    var minimumFrameRate: Double

    var preferredPixelWidth: Int?
    var preferredPixelHeight: Int?
    var preferredFrameRate: Double?

    var hasExplicitPreferredFormat: Bool {
        preferredPixelWidth != nil && preferredPixelHeight != nil && preferredFrameRate != nil
    }

    nonisolated static let defaultForLaunch = CaptureVideoFormatPreferences(
        minimumFrameRate: 60,
        preferredPixelWidth: nil,
        preferredPixelHeight: nil,
        preferredFrameRate: nil
    )

    nonisolated static func loadFromStorage() -> CaptureVideoFormatPreferences {
        let defaults = UserDefaults.standard
        let minFPS = defaults.double(forKey: CaptureVideoFormatUserDefaultsKeys.minimumFrameRateKey)
        let minimumFrameRate = (minFPS > 0 && minFPS.isFinite) ? minFPS : defaultForLaunch.minimumFrameRate

        let storedWidth = defaults.integer(forKey: CaptureVideoFormatUserDefaultsKeys.preferredWidthKey)
        let storedHeight = defaults.integer(forKey: CaptureVideoFormatUserDefaultsKeys.preferredHeightKey)
        let fps = defaults.double(forKey: CaptureVideoFormatUserDefaultsKeys.preferredFrameRateKey)

        let width: Int? = storedWidth > 0 ? storedWidth : nil
        let height: Int? = storedHeight > 0 ? storedHeight : nil
        let frameRate: Double? = (fps > 0 && fps.isFinite) ? fps : nil

        let triple = (width != nil && height != nil && frameRate != nil)
        return CaptureVideoFormatPreferences(
            minimumFrameRate: minimumFrameRate,
            preferredPixelWidth: triple ? width : nil,
            preferredPixelHeight: triple ? height : nil,
            preferredFrameRate: triple ? frameRate : nil
        )
    }

    nonisolated func saveToStorage() {
        let defaults = UserDefaults.standard
        defaults.set(minimumFrameRate, forKey: CaptureVideoFormatUserDefaultsKeys.minimumFrameRateKey)
        if let pixelWidth = preferredPixelWidth,
           let pixelHeight = preferredPixelHeight,
           let fps = preferredFrameRate {
            defaults.set(pixelWidth, forKey: CaptureVideoFormatUserDefaultsKeys.preferredWidthKey)
            defaults.set(pixelHeight, forKey: CaptureVideoFormatUserDefaultsKeys.preferredHeightKey)
            defaults.set(fps, forKey: CaptureVideoFormatUserDefaultsKeys.preferredFrameRateKey)
        } else {
            defaults.set(0, forKey: CaptureVideoFormatUserDefaultsKeys.preferredWidthKey)
            defaults.set(0, forKey: CaptureVideoFormatUserDefaultsKeys.preferredHeightKey)
            defaults.set(0.0, forKey: CaptureVideoFormatUserDefaultsKeys.preferredFrameRateKey)
        }
    }

    nonisolated func withPreferredFormat(
        width: Int?,
        height: Int?,
        frameRate: Double?
    ) -> CaptureVideoFormatPreferences {
        let triple = width != nil && height != nil && frameRate != nil
        return CaptureVideoFormatPreferences(
            minimumFrameRate: minimumFrameRate,
            preferredPixelWidth: triple ? width : nil,
            preferredPixelHeight: triple ? height : nil,
            preferredFrameRate: triple ? frameRate : nil
        )
    }
}

enum CaptureFormatSelector: Sendable {
    nonisolated static func applyPreferredFormat(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) throws {
        logAllFormats(device: device, preferences: preferences)
        if try applyExplicitSelectionIfPossible(device: device, preferences: preferences) {
            return
        }
        try applyFormatAndFrameDuration(device: device, preferences: preferences)
    }

    /// Re-selects and re-applies both the active format and frame duration.
    /// On macOS the UVC driver resets both when the session starts; call this
    /// (under `lockForConfiguration`) after `session.startRunning()`.
    /// Caller must hold `device.lockForConfiguration()` before calling.
    nonisolated static func reapplyFormatAndFrameDuration(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) throws {
        if try applyExplicitSelectionIfPossible(device: device, preferences: preferences) {
            return
        }
        try applyFormatAndFrameDuration(device: device, preferences: preferences)
    }

    /// Shared core used by both initial apply and post-start re-apply (no logging).
    private nonisolated static func applyFormatAndFrameDuration(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) throws {
        guard let format = bestFormat(device: device, preferences: preferences) else {
            throw CaptureFormatError.noSupportedFormat
        }

        let maxFPS = format.maxFrameRate
        logSelectedFormat(format, targetFPS: maxFPS)
        device.activeFormat = format
        applyFrameDuration(to: device, format: format, targetFPS: maxFPS)
    }

    /// Returns grouped resolution / frame rate choices for nested menus.
    nonisolated static func resolutionMenuOptions(device: AVCaptureDevice) -> [CaptureVideoFormatMenuResolution] {
        struct PixelKey: Hashable {
            let width: Int
            let height: Int
        }

        var ratesByPixel: [PixelKey: Set<Double>] = [:]
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let key = PixelKey(width: Int(dims.width), height: Int(dims.height))
            var rates = ratesByPixel[key, default: []]
            for range in format.videoSupportedFrameRateRanges {
                rates.formUnion(CaptureVideoFormatMenuRates.fromRange(range))
            }
            ratesByPixel[key] = rates
        }

        let sortedKeys = ratesByPixel.keys.sorted {
            if $0.width != $1.width { return $0.width > $1.width }
            return $0.height > $1.height
        }
        return sortedKeys.map { key in
            let descending = CaptureVideoFormatMenuRates.deduplicatedDescending(ratesByPixel[key] ?? [])
            return CaptureVideoFormatMenuResolution(
                width: key.width,
                height: key.height,
                frameRatesDescending: descending
            )
        }
    }

    nonisolated static func canApplyExplicitFormat(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) -> Bool {
        guard let pixelWidth = preferences.preferredPixelWidth,
              let pixelHeight = preferences.preferredPixelHeight,
              let fps = preferences.preferredFrameRate
        else { return false }
        return locateFormatForExplicitSelection(
            device: device,
            width: pixelWidth,
            height: pixelHeight,
            frameRate: fps
        ) != nil
    }

    /// Values the UI should show for the current device and stored preferences (explicit if valid, else auto pick).
    nonisolated static func effectiveFormatForDisplay(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) -> CaptureVideoFormatEffectiveDisplay? {
        if canApplyExplicitFormat(device: device, preferences: preferences),
           let pixelWidth = preferences.preferredPixelWidth,
           let pixelHeight = preferences.preferredPixelHeight,
           let fps = preferences.preferredFrameRate {
            return CaptureVideoFormatEffectiveDisplay(
                width: pixelWidth,
                height: pixelHeight,
                frameRate: fps
            )
        }
        guard let format = bestFormat(device: device, preferences: preferences) else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let fps = format.maxFrameRate
        return CaptureVideoFormatEffectiveDisplay(
            width: Int(dims.width),
            height: Int(dims.height),
            frameRate: fps
        )
    }

    private nonisolated static func applyExplicitSelectionIfPossible(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) throws -> Bool {
        guard let pixelWidth = preferences.preferredPixelWidth,
              let pixelHeight = preferences.preferredPixelHeight,
              let fps = preferences.preferredFrameRate
        else { return false }

        guard let format = locateFormatForExplicitSelection(
            device: device,
            width: pixelWidth,
            height: pixelHeight,
            frameRate: fps
        ) else {
            return false
        }

        logSelectedFormat(format, targetFPS: fps)
        device.activeFormat = format
        applyFrameDuration(to: device, format: format, targetFPS: fps)
        return true
    }

    private nonisolated static func locateFormatForExplicitSelection(
        device: AVCaptureDevice,
        width: Int,
        height: Int,
        frameRate: Double
    ) -> AVCaptureDevice.Format? {
        let candidates = device.formats.filter {
            let dims = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return Int(dims.width) == width && Int(dims.height) == height
        }
        guard !candidates.isEmpty else { return nil }

        let epsilon = 0.5
        if let supported = candidates.first(where: { format in
            format.videoSupportedFrameRateRanges.contains { range in
                frameRate >= range.minFrameRate - epsilon && frameRate <= range.maxFrameRate + epsilon
            }
        }) {
            return supported
        }

        return candidates.max(by: { $0.maxFrameRate < $1.maxFrameRate })
    }

    /// Returns the best format for the given preferences, or `nil` if none qualify.
    nonisolated static func bestFormat(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) -> AVCaptureDevice.Format? {
        let minFPS = preferences.minimumFrameRate

        let qualifying = device.formats.filter { $0.maxFrameRate >= minFPS - 0.5 }
        let candidates = qualifying.isEmpty ? device.formats : qualifying
        guard !candidates.isEmpty else { return nil }

        let maxFPS = candidates.map(\.maxFrameRate).max() ?? 0
        let atMaxFPS = candidates.filter { $0.maxFrameRate >= maxFPS - 0.5 }

        return atMaxFPS.max(by: widthFirstResolutionSort)
    }

    private nonisolated static func widthFirstResolutionSort(
        _ lhs: AVCaptureDevice.Format,
        _ rhs: AVCaptureDevice.Format
    ) -> Bool {
        let lhsDims = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
        let rhsDims = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
        if lhsDims.width != rhsDims.width { return lhsDims.width < rhsDims.width }
        return lhsDims.height < rhsDims.height
    }

    private nonisolated static func applyFrameDuration(
        to device: AVCaptureDevice,
        format: AVCaptureDevice.Format,
        targetFPS: Double
    ) {
        let maxAvailable = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        let desiredFPS = min(targetFPS, maxAvailable)

        guard let range = format.bestFrameRateRange(for: desiredFPS) else { return }

        let targetCap = min(desiredFPS, range.maxFrameRate)
        let epsilon = 0.5
        if targetCap >= range.maxFrameRate - epsilon {
            device.activeVideoMinFrameDuration = range.minFrameDuration
            device.activeVideoMaxFrameDuration = range.minFrameDuration
            logAppliedFrameDuration(device: device, targetFPS: targetCap)
        } else if targetCap <= range.minFrameRate + epsilon {
            device.activeVideoMinFrameDuration = range.maxFrameDuration
            device.activeVideoMaxFrameDuration = range.maxFrameDuration
            logAppliedFrameDuration(device: device, targetFPS: targetCap)
        } else if let duration = exactFrameDuration(for: targetCap, within: range) {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            logAppliedFrameDuration(device: device, targetFPS: targetCap)
        }
    }

    private nonisolated static func exactFrameDuration(for fps: Double, within range: AVFrameRateRange) -> CMTime? {
        guard fps > 0, fps.isFinite else { return nil }
        let duration = CMTime(value: CMTimeValue((60_000 / fps).rounded()), timescale: 60_000)
        guard duration.seconds >= range.minFrameDuration.seconds - 0.000_001,
              duration.seconds <= range.maxFrameDuration.seconds + 0.000_001
        else { return nil }
        return duration
    }

    private nonisolated static func logAppliedFrameDuration(device: AVCaptureDevice, targetFPS: Double) {
        let minDuration = device.activeVideoMinFrameDuration
        let maxDuration = device.activeVideoMaxFrameDuration
        let minFPS = minDuration.seconds > 0 ? 1 / minDuration.seconds : 0
        let maxFPS = maxDuration.seconds > 0 ? 1 / maxDuration.seconds : 0
        #if DEBUG
        NSLog(
            "[VideoFrameDuration] applied: targetFPS=\(targetFPS), " +
            "minDuration=\(minDuration), maxDuration=\(maxDuration), " +
            "minFPS=\(minFPS), maxFPS=\(maxFPS)"
        )
        #endif
    }

    private nonisolated static func logAllFormats(
        device: AVCaptureDevice,
        preferences: CaptureVideoFormatPreferences
    ) {
        #if os(macOS)
        let minFPS = preferences.minimumFrameRate
        let best = bestFormat(device: device, preferences: preferences)

        let sorted = device.formats.sorted {
            if $0.maxFrameRate != $1.maxFrameRate { return $0.maxFrameRate > $1.maxFrameRate }
            return $0.pixelCount > $1.pixelCount
        }

        #if DEBUG
        NSLog("[VideoFormats] macOS available formats (minimum \(minFPS) fps):")
        for format in sorted {
            let qualifies = format.maxFrameRate >= minFPS - 0.5
            let marker = !qualifies ? "✗" : (format === best ? "→" : "✓")
            NSLog("  \(marker) \(videoFormatDescription(format))")
        }
        #endif
        #endif
    }

    private nonisolated static func logSelectedFormat(
        _ format: AVCaptureDevice.Format,
        targetFPS: Double
    ) {
        #if DEBUG
        NSLog("[VideoFormats] selected: \(videoFormatDescription(format)), targetFPS=\(targetFPS)")
        #endif
    }

    nonisolated static func videoFormatDescription(_ format: AVCaptureDevice.Format) -> String {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let ranges = format.videoSupportedFrameRateRanges.map { range in
            "\(range.minFrameRate)-\(range.maxFrameRate)fps"
        }
        return "\(dims.width)x\(dims.height) \(ranges)"
    }
}

private enum CaptureFormatError: LocalizedError {
    case noSupportedFormat

    var errorDescription: String? {
        switch self {
        case .noSupportedFormat:
            return "No supported video format was found for this device."
        }
    }
}

private extension AVCaptureDevice.Format {
    nonisolated var maxFrameRate: Double {
        videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
    }

    nonisolated var pixelCount: Int {
        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        return Int(dims.width) * Int(dims.height)
    }

    nonisolated func bestFrameRateRange(for fps: Double) -> AVFrameRateRange? {
        let epsilon = 0.5
        let compatibleRanges = videoSupportedFrameRateRanges.filter { range in
            range.minFrameRate <= fps + epsilon && range.maxFrameRate >= fps - epsilon
        }
        if let nearestCompatible = compatibleRanges.min(by: {
            abs($0.maxFrameRate - fps) < abs($1.maxFrameRate - fps)
        }) {
            return nearestCompatible
        }

        return videoSupportedFrameRateRanges.min(by: {
            abs($0.maxFrameRate - fps) < abs($1.maxFrameRate - fps)
        })
    }
}
