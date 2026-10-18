//
//  CaptureDeviceIdentification.swift
//  Consolation
//

import AVFoundation
import Foundation

// MARK: - USB UVC capture device identification

/// Returns `true` only for a USB video capture device, such as Elgato Game Capture HD60 X.
nonisolated func deviceIsUSBVideoCapture(_ device: AVCaptureDevice) -> Bool {
    guard device.deviceType == .external else { return false }

    if #available(macOS 13.0, iOS 16.0, macCatalyst 16.0, *) {
        if device.isContinuityCamera { return false }
    }

    if device.localizedName.localizedCaseInsensitiveContains("camera") { return false }

    return true
}

enum CaptureSessionError: LocalizedError {
    case noVideoDevice
    case cannotAddVideoInput

    var errorDescription: String? {
        switch self {
        case .noVideoDevice:
            return "No video capture device was found."
        case .cannotAddVideoInput:
            return "This capture device cannot be used as a video input."
        }
    }
}
