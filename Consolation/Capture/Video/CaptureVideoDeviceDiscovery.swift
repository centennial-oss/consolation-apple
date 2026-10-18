//
//  CaptureVideoDeviceDiscovery.swift
//  Consolation
//

import AVFoundation
import Foundation

enum CaptureVideoDeviceDiscovery {
    nonisolated static func allVideoDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .external
        ]
        #if os(iOS)
        types.insert(.builtInUltraWideCamera, at: 1)
        #endif
        if #available(macOS 13.0, iOS 16.0, *) {
            types.append(.continuityCamera)
        }
        return types
    }

    nonisolated static func discoverSortedVideoDevices() -> [AVCaptureDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: allVideoDeviceTypes(),
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.sorted {
            $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
        }
    }

    /// First USB UVC capture device name, or simulator camera name in the simulator.
    nonisolated static func connectedUSBVideoCaptureDisplayName() -> String? {
        let types: [AVCaptureDevice.DeviceType] = [.external]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        if let device = discovery.devices.first(where: deviceIsUSBVideoCapture) {
            return device.localizedName
        }

        #if targetEnvironment(simulator)
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.first?.localizedName
        #else
        return nil
        #endif
    }
}
