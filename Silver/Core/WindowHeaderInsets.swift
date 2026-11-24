import Foundation

public struct WindowHeaderInsets: Equatable, Sendable {
    public let contentOverlap: CGFloat
    public let sidebarTop: CGFloat
    public init(fullScreen: Bool, measuredTitlebar: CGFloat) {
        // Full-screen content already sits below the system's revealable chrome.
        // Applying the windowed overlap there would hide the custom header rows.
        contentOverlap = fullScreen || !measuredTitlebar.isFinite ? 0 : max(0, measuredTitlebar)
        sidebarTop = fullScreen ? 0 : 52
    }
}
