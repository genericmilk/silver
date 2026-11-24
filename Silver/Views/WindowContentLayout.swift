import SwiftUI

private final class WindowLayoutObservers: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
    func clear() { for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens.removeAll() }
    deinit { clear() }
}

/// Keeps the app's header rows below full-screen system chrome and extends them
/// into the transparent native title bar only while the window is not full screen.
struct WindowContentLayout: NSViewRepresentable {
    @Environment(Preferences.self) private var preferences
    func makeNSView(context: Context) -> LayoutView { LayoutView() }
    func updateNSView(_ view: LayoutView, context: Context) {
        view.onLayout = { insets, fullScreen in
            if abs(preferences.titlebarInset - insets.contentOverlap) > 0.5 { preferences.titlebarInset = insets.contentOverlap }
            if preferences.windowFullScreen != fullScreen { preferences.windowFullScreen = fullScreen }
        }
        view.apply()
    }

    final class LayoutView: NSView {
        var onLayout: ((WindowHeaderInsets, Bool) -> Void)?
        private var lastInsets: WindowHeaderInsets?
        private var lastFullScreen: Bool?
        private weak var observedWindow: NSWindow?
        private var hidToolbar = false
        private let observations = WindowLayoutObservers()
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observations.clear()
            observedWindow = nil
            lastInsets = nil
            lastFullScreen = nil
            apply()
        }
        override func layout() { super.layout(); apply() }
        func apply() {
            guard let window, let content = window.contentView else { return }
            if observedWindow !== window {
                observations.clear()
                observedWindow = window
                for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification, NSWindow.didUpdateNotification] {
                    observations.tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.apply() }
                    })
                }
            }
            window.titlebarAppearsTransparent = true
            let fullScreen = window.styleMask.contains(.fullScreen)
            if fullScreen, let toolbar = window.toolbar, toolbar.isVisible {
                hidToolbar = true
                toolbar.isVisible = false
            } else if !fullScreen, hidToolbar {
                hidToolbar = false
                window.toolbar?.isVisible = true
            }
            let insets = WindowHeaderInsets(fullScreen: fullScreen, measuredTitlebar: content.frame.maxY - window.contentLayoutRect.maxY)
            guard lastInsets != insets || lastFullScreen != fullScreen else { return }
            lastInsets = insets
            lastFullScreen = fullScreen
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastInsets == insets, self.lastFullScreen == fullScreen else { return }
                self.onLayout?(insets, fullScreen)
            }
        }
    }
}
