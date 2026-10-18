//
//  CaptureVideoPreviewDeviceContext.swift
//  Consolation
//

import AVFoundation
import Foundation

struct CaptureVideoPreviewDeviceContext {
    let deviceID: String?
    let isUSBVideoCapture: Bool

    init(session: AVCaptureSession?) {
        let device = session?.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.video) }?
            .device
        deviceID = device?.uniqueID
        isUSBVideoCapture = device.map(deviceIsUSBVideoCapture) ?? false
    }

    var isCamera: Bool {
        deviceID != nil && !isUSBVideoCapture
    }
}
