import SwiftUI

struct AppearanceOptions: Codable, Equatable {
    var interfaceFont = "system"
    var interfaceSize = 13.0
    var density = "standard"
    var codeFont = "SF Mono"
    var codeSize = 12.0
    var codeLineSpacing = 2.0
    var wrapLines = false
    var diffBackgrounds = true
    var diffPalette = "classic"
    var contextLines = 3
    var expandContext = false
    var showSidebarBranches = true
    var showFilePaths = true
    var showFileStatus = true
    var showProjectPaths = true
    var showProjectDates = true
    var projectSort = "recent"
    var singleClickProjects = false
    var defaultSection = "Changes"
    var sidebarInitiallyVisible = true
    var useProjectAccent = false
    var commitEditorHeight = 80.0
    var animateIcons = true

    var fontDesign: Font.Design {
        switch interfaceFont { case "rounded": .rounded; case "serif": .serif; case "monospaced": .monospaced; default: .default }
    }
    var rowPadding: CGFloat { density == "compact" ? 2 : density == "relaxed" ? 10 : 5 }
    var rowHeight: CGFloat { density == "compact" ? 22 : density == "relaxed" ? 36 : 28 }
    var codeNSFont: NSFont {
        codeFont == "SF Mono" ? .monospacedSystemFont(ofSize: codeSize, weight: .regular) : NSFont(name: codeFont, size: codeSize) ?? .monospacedSystemFont(ofSize: codeSize, weight: .regular)
    }
    var additionColor: NSColor {
        switch diffPalette { case "accessible": .systemTeal; case "subtle": .labelColor; default: .systemGreen }
    }
    var deletionColor: NSColor {
        switch diffPalette { case "accessible": .systemPink; case "subtle": .secondaryLabelColor; default: .systemRed }
    }
}
