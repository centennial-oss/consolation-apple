import SwiftUI

extension ContentView {
    var shouldShowStatusLine: Bool {
        switch capture.state {
        case .requestingPermission, .failed:
            return true
        default:
            return false
        }
    }

    func cancelHoverHideTask() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    func revealTransientChromeIfNeeded() {
        guard isUIHidden else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            isUIHidden = false
        }
        #if os(macOS)
        window?.standardWindowButton(.closeButton)?.superview?.animator().alphaValue = 1.0
        #endif
    }

    func cancelAutoHideChrome() {
        cancelHoverHideTask()
        revealTransientChromeIfNeeded()
    }

    /// Auto-hide overlays and traffic-light dimming only apply while actively watching.
    func resetHoverTimer() {
        #if os(macOS)
        guard !isAppMenuTracking else {
            cancelHoverHideTask()
            revealTransientChromeIfNeeded()
            return
        }
        #endif

        guard !isPlaybackControlsInteractionActive, !isPlaybackControlsHoverActive else {
            cancelHoverHideTask()
            revealTransientChromeIfNeeded()
            return
        }

        #if os(iOS)
        guard !isPlaybackSettingsMenuPresented else {
            cancelHoverHideTask()
            revealTransientChromeIfNeeded()
            return
        }
        #endif

        guard capture.state == .running else {
            cancelAutoHideChrome()
            return
        }

        cancelHoverHideTask()
        revealTransientChromeIfNeeded()

        hoverTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, capture.state == .running else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                isUIHidden = true
            }
            #if os(macOS)
            window?.standardWindowButton(.closeButton)?.superview?.animator().alphaValue = 0.0
            NSCursor.setHiddenUntilMouseMoves(true)
            #endif
        }
    }
}

#Preview {
    ContentView(capture: CaptureSessionManager())
}
