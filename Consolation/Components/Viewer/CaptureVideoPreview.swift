//
//  CaptureVideoPreview.swift
//  Consolation
//

import AVFoundation
import SwiftUI
private let maxPreviewZoomScale: CGFloat = 1.175 * 1.5
private func previewZoomScale(for zoomLevel: Double) -> CGFloat {
    1 + ((maxPreviewZoomScale - 1) * normalizedPreviewZoomLevel(for: zoomLevel))
}
private func normalizedPreviewZoomLevel(for zoomLevel: Double) -> CGFloat { CGFloat(min(max(zoomLevel, 0), 100) / 100) }

#if os(macOS)
import AppKit

struct CaptureVideoPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let isRunning: Bool
    let previewZoomLevel: Double
    let previewPanOffset: CGSize
    let onDoubleClick: () -> Void
    let onPanDelta: (CGSize) -> Void

    init(
        session: AVCaptureSession,
        isRunning: Bool,
        previewZoomLevel: Double = 0,
        previewPanOffset: CGSize = .zero,
        onDoubleClick: @escaping () -> Void = {},
        onPanDelta: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.session = session
        self.isRunning = isRunning
        self.previewZoomLevel = previewZoomLevel
        self.previewPanOffset = previewPanOffset
        self.onDoubleClick = onDoubleClick
        self.onPanDelta = onPanDelta
    }

    func makeNSView(context: Context) -> MacPreviewView {
        let view = MacPreviewView(frame: .zero)
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.setPreviewZoom(scale: previewZoomScale(for: previewZoomLevel), panOffset: previewPanOffset)
        view.onDoubleClick = onDoubleClick
        view.onPanDelta = onPanDelta
        view.applyPreviewConnectionSettings()
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: MacPreviewView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        if nsView.previewLayer.videoGravity != .resizeAspect {
            nsView.previewLayer.videoGravity = .resizeAspect
        }
        nsView.setPreviewZoom(scale: previewZoomScale(for: previewZoomLevel), panOffset: previewPanOffset)
        nsView.onDoubleClick = onDoubleClick
        nsView.onPanDelta = onPanDelta
        nsView.applyPreviewConnectionSettings()

        // Force the layer to recalculate its internal projection matrix when the video starts.
        // AVCaptureVideoPreviewLayer has a known bug where it fails to naturally rescale
        // incoming video feeds to fill the view if the inputs attach while the view was statically sized.
        if isRunning, !context.coordinator.wasRunning {
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                nsView.previewLayer.frame = .zero
                nsView.resizePreviewLayer()
                CATransaction.commit()
                nsView.applyPreviewConnectionSettings()
            }
        }
        context.coordinator.wasRunning = isRunning
    }

    final class Coordinator {
        var wasRunning = false
    }
}

#elseif os(iOS)
import UIKit

final class IOSPreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private var previewZoomScale: CGFloat = 1
    private var previewPanOffset: CGSize = .zero
    private var notificationObservations: [Task<Void, Never>] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.addSublayer(previewLayer)
        let center = NotificationCenter.default
        let transformChanged = CaptureVideoPreviewTransformUserDefaults.changedNotification
        notificationObservations = [
            Task { [weak self] in
                for await _ in center.notifications(named: transformChanged) {
                    self?.applyPreviewConnectionSettings()
                }
            },
            Task { [weak self] in
                for await _ in center.notifications(named: UIDevice.orientationDidChangeNotification) {
                    self?.schedulePreviewConnectionSettingsRefresh()
                }
            }
        ]
    }

    deinit {
        notificationObservations.forEach { $0.cancel() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resizePreviewLayer()
        applyPreviewConnectionSettings()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPreviewConnectionSettings()
        schedulePreviewConnectionSettingsRefresh()
    }

    func setPreviewActive(_ active: Bool, session: AVCaptureSession?) {
        isHidden = !active
        previewLayer.session = active ? session : nil
        if active {
            applyPreviewConnectionSettings()
        }
    }

    func setPreviewZoom(scale: CGFloat, panOffset: CGSize) {
        let clampedScale = max(scale, 1)
        guard previewZoomScale != clampedScale || previewPanOffset != panOffset else { return }
        previewZoomScale = clampedScale
        previewPanOffset = panOffset
        resizePreviewLayer()
    }

    func resizePreviewLayer() {
        let scaledWidth = bounds.width * previewZoomScale
        let scaledHeight = bounds.height * previewZoomScale
        let maxOffsetX = (scaledWidth - bounds.width) / 2
        let maxOffsetY = (scaledHeight - bounds.height) / 2
        let offsetX = max(-maxOffsetX, min(maxOffsetX, previewPanOffset.width))
        let offsetY = max(-maxOffsetY, min(maxOffsetY, previewPanOffset.height))
        let scaledFrame = CGRect(
            x: (bounds.width - scaledWidth) / 2 + offsetX,
            y: (bounds.height - scaledHeight) / 2 + offsetY,
            width: scaledWidth,
            height: scaledHeight
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = scaledFrame
        CATransaction.commit()
    }

    /// USB capture feeds are already display-oriented; built-in cameras need interface-orientation correction.
    func applyPreviewConnectionSettings() {
        guard let connection = previewLayer.connection else { return }
        let context = activeVideoDeviceContext
        let transform = CaptureVideoPreviewTransformUserDefaults.load(forDeviceID: context.deviceID)
        let defaultMirrors = defaultMirrorOptions(for: context)
        let isHorizontallyMirrored = defaultMirrors.contains(.horizontal) != transform.mirrors.contains(.horizontal)
        let isVerticallyMirrored = defaultMirrors.contains(.vertical) != transform.mirrors.contains(.vertical)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isHorizontallyMirrored
        }
        #if os(iOS)
        let defaultAngle = context.isUSBVideoCapture ? 0 : previewRotationAngleForCurrentInterfaceOrientation()
        let angle = normalizedRotationAngle(defaultAngle + CGFloat(transform.rotation.rawValue))
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        } else {
            #if DEBUG
            NSLog("[iOSVideo]: preview rotation angle \(angle) is not supported")
            #endif
        }
        #endif
        applyLayerMirrorTransform(
            horizontal: connection.isVideoMirroringSupported ? false : isHorizontallyMirrored,
            vertical: isVerticallyMirrored
        )
    }
}

struct CaptureVideoPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let isRunning: Bool
    let previewZoomLevel: Double
    let previewPanOffset: CGSize
    let onDoubleClick: () -> Void
    // onPanDelta unused on iOS (gesture handled by SwiftUI layer); present for call-site uniformity.
    let onPanDelta: (CGSize) -> Void

    init(
        session: AVCaptureSession,
        isRunning: Bool,
        previewZoomLevel: Double = 0,
        previewPanOffset: CGSize = .zero,
        onDoubleClick: @escaping () -> Void = {},
        onPanDelta: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.session = session
        self.isRunning = isRunning
        self.previewZoomLevel = previewZoomLevel
        self.previewPanOffset = previewPanOffset
        self.onDoubleClick = onDoubleClick
        self.onPanDelta = onPanDelta
    }

    func makeUIView(context: Context) -> IOSPreviewView {
        let view = IOSPreviewView(frame: .zero)
        view.previewLayer.videoGravity = .resizeAspect
        view.setPreviewZoom(scale: previewZoomScale(for: previewZoomLevel), panOffset: previewPanOffset)
        view.setPreviewActive(isRunning, session: session)
        return view
    }

    func updateUIView(_ uiView: IOSPreviewView, context: Context) {
        if uiView.previewLayer.videoGravity != .resizeAspect {
            uiView.previewLayer.videoGravity = .resizeAspect
        }
        uiView.setPreviewZoom(scale: previewZoomScale(for: previewZoomLevel), panOffset: previewPanOffset)
        uiView.setPreviewActive(isRunning, session: session)

        if isRunning {
            DispatchQueue.main.async {
                uiView.resizePreviewLayer()
                uiView.applyPreviewConnectionSettings()
            }
        } else {
            uiView.applyPreviewConnectionSettings()
        }
    }

    static func dismantleUIView(_ uiView: IOSPreviewView, coordinator: ()) {
        uiView.setPreviewActive(false, session: nil)
    }
}

#endif
