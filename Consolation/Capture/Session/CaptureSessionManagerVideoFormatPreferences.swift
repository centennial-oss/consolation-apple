//
//  CaptureSessionManagerVideoFormatPreferences.swift
//  Consolation
//

import AVFoundation
import Foundation

extension CaptureSessionManager {
    func applyFormatPreferencesForSelectedDevice(uniqueID: String) {
        guard let device = AVCaptureDevice(uniqueID: uniqueID) else {
            clearExplicitFormatPreference()
            return
        }

        if let saved = CaptureVideoFormatUserDefaults.loadPreferredFormat(
            forDeviceID: uniqueID,
            minimumFrameRate: formatPreferences.minimumFrameRate
        ),
           CaptureFormatSelector.canApplyExplicitFormat(device: device, preferences: saved) {
            formatPreferences = saved
            formatPreferences.saveToStorage()
            return
        }

        clearExplicitFormatPreference()
    }

    private func clearExplicitFormatPreference() {
        formatPreferences = formatPreferences.withPreferredFormat(width: nil, height: nil, frameRate: nil)
        formatPreferences.saveToStorage()
    }
}
