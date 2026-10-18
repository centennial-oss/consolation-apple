//
//  MacPreviewView.swift
//  Consolation
//

#if os(macOS)
import AppKit
import AVFoundation

final class MacPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var onDoubleClick: () -> Void = {}
    var onPanDelta: (CGSize) -> Void = { _ in }
    private var previewZoomScale: CGFloat = 1
    private var previewPanOffset: CGSize = .zero
    private var shiftDragOrigin: NSPoint?
    private var transformObservation: Task<Void, Never>?

    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(previewLayer)
        previewLayer.videoGravity = .resizeAspect
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        transformObservation = Task { [weak self] in
            let name = CaptureVideoPreviewTransformUserDefaults.changedNotification
            for await _ in NotificationCenter.default.notifications(named: name) {
                self?.applyPreviewConnectionSettings()
            }
        }
    }

    deinit {
        transformObservation?.cancel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        resizePreviewLayer()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizePreviewLayer()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        resizePreviewLayer()
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        resizePreviewLayer()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
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

    func setPreviewZoom(scale: CGFloat, panOffset: CGSize) {
        let clampedScale = max(scale, 1)
        guard previewZoomScale != clampedScale || previewPanOffset != panOffset else { return }
        previewZoomScale = clampedScale
        previewPanOffset = panOffset
        resizePreviewLayer()
    }

    func applyPreviewConnectionSettings() {
        guard let connection = previewLayer.connection else { return }
        let context = activeVideoDeviceContext
        let transform = CaptureVideoPreviewTransformUserDefaults.load(forDeviceID: context.deviceID)
        let isHorizontallyMirrored = context.isCamera != transform.mirrors.contains(.horizontal)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isHorizontallyMirrored
        }
        if connection.isVideoRotationAngleSupported(CGFloat(transform.rotation.rawValue)) {
            connection.videoRotationAngle = CGFloat(transform.rotation.rawValue)
        }
        applyLayerMirrorTransform(
            horizontal: connection.isVideoMirroringSupported ? false : isHorizontallyMirrored,
            vertical: transform.mirrors.contains(.vertical)
        )
    }

    private var activeVideoDeviceContext: CaptureVideoPreviewDeviceContext {
        CaptureVideoPreviewDeviceContext(session: previewLayer.session)
    }

    private func applyLayerMirrorTransform(horizontal: Bool, vertical: Bool) {
        previewLayer.setAffineTransform(
            CGAffineTransform(scaleX: horizontal ? -1 : 1, y: vertical ? -1 : 1)
        )
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
            return
        }
        if event.modifierFlags.contains(.shift) {
            shiftDragOrigin = event.locationInWindow
            return
        }
        guard let window else {
            super.mouseDown(with: event)
            return
        }
        window.performDrag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = shiftDragOrigin else {
            super.mouseDragged(with: event)
            return
        }
        let current = event.locationInWindow
        let delta = CGSize(width: current.x - origin.x, height: current.y - origin.y)
        shiftDragOrigin = current
        onPanDelta(delta)
    }

    override func mouseUp(with event: NSEvent) {
        if shiftDragOrigin != nil {
            shiftDragOrigin = nil
            return
        }
        super.mouseUp(with: event)
    }
}
#endif
