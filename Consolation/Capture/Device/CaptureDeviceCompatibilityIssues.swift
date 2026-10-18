//
//  CaptureDeviceCompatibilityIssues.swift
//  Consolation
//

import AVFoundation
import Foundation

enum CaptureDeviceCompatibilityPlatform: String, Sendable {
    case ipad = "iPad"
    case macOS = "macOS"

    nonisolated static var current: CaptureDeviceCompatibilityPlatform {
        #if os(iOS)
        .ipad
        #else
        .macOS
        #endif
    }
}

struct CaptureDeviceCompatibilityIssue: Identifiable, Sendable {
    let id: String
    let platform: CaptureDeviceCompatibilityPlatform
    let manufacturer: String?
    let uniqueID: String?
    let modelID: String?
    let summary: String

    nonisolated func matches(
        device: AVCaptureDevice,
        platform currentPlatform: CaptureDeviceCompatibilityPlatform
    ) -> Bool {
        guard platform == currentPlatform else { return false }
        return matchesIfProvided(needle: manufacturer, haystack: device.manufacturer)
            && matchesIfProvided(needle: uniqueID, haystack: device.uniqueID)
            && matchesIfProvided(needle: modelID, haystack: device.modelID)
    }

    private nonisolated func matchesIfProvided(needle: String?, haystack: String) -> Bool {
        guard let needle, !needle.isEmpty else { return true }
        return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

enum CaptureDeviceCompatibilityIssues: Sendable {
    nonisolated static let known: [CaptureDeviceCompatibilityIssue] = [
        CaptureDeviceCompatibilityIssue(
            id: "ipad-macrosilicon-2109",
            platform: .ipad,
            manufacturer: "macrosilicon",
            uniqueID: "2109",
            modelID: nil,
            summary: "MacroSilicon 2109 capture devices may not deliver the requested frame rate " +
                "on iPad when using 1920x1080 at 60p. During playback, \(AppIdentifier.name) may " +
                "report that the card is operating at 30p. If you " +
                "experience issues and want to operate at true 60p, use 1280x720."
        ),
        CaptureDeviceCompatibilityIssue(
            id: "macos-macrosilicon-2109",
            platform: .macOS,
            manufacturer: "macrosilicon",
            uniqueID: "2109",
            modelID: nil,
            summary: "UVC devices with the MacroSilicon 2109 chip do not deliver true 60p at " +
                "1920x1080. They internally process at 30p and duplicate every frame " +
                "to simulate 60p. You may experience choppy or inconsistent video quality. If you " +
                "experience issues and want to operate at true 60p, use 1280x720."
        )
    ]

    nonisolated static func issue(for device: AVCaptureDevice) -> CaptureDeviceCompatibilityIssue? {
        known.first { $0.matches(device: device, platform: .current) }
    }
}
