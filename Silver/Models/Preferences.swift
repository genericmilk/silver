import SwiftUI

enum ProjectColor: String, CaseIterable, Codable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .graphite: .secondary
        }
    }
    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .graphite: .systemGray
        }
    }
}

struct Project: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var path: String
    var name: String
    var color: ProjectColor = .blue
    var symbol: String = "folder.fill"
    var iconFile: String?
    var pinned = false
    var lastOpened = Date()
    var url: URL { URL(fileURLWithPath: path) }
    var displayPath: String {
        (path as NSString).abbreviatingWithTildeInPath
    }
    static let symbols = ["folder.fill", "chevron.left.forwardslash.chevron.right", "app.fill", "swift", "globe", "terminal.fill", "gamecontroller.fill", "book.closed.fill", "music.note", "camera.fill", "hammer.fill", "leaf.fill"]
}

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case apple, claude, openAI, openRouter
    var id: String { rawValue }
    var name: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .claude: "Claude"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        }
    }
    var defaultModel: String {
        switch self {
        case .apple: ""
        case .claude: "claude-sonnet-4-5"
        case .openAI: "gpt-4.1-mini"
        case .openRouter: "anthropic/claude-sonnet-4.5"
        }
    }
}

@MainActor @Observable
final class Preferences {
    var titlebarInset: CGFloat = 52
    var windowFullScreen = false
    var appearance: String { didSet { UserDefaults.standard.set(appearance, forKey: "appearance") } }
    var accent: ProjectColor { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
    var provider: AIProvider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") } }
    var models: [String: String] { didSet { UserDefaults.standard.set(models, forKey: "models") } }
    var instruction: String { didSet { UserDefaults.standard.set(instruction, forKey: "commitInstruction") } }
    var diffStyle: String { didSet { UserDefaults.standard.set(diffStyle, forKey: "diffStyle") } }
    var lineNumbers: Bool { didSet { UserDefaults.standard.set(lineNumbers, forKey: "lineNumbers") } }
    var layout: AppearanceOptions {
        didSet { if let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: "layoutOptions") } }
    }
    var scheme: ColorScheme? { appearance == "system" ? nil : appearance == "dark" ? .dark : .light }
    init() {
        let defaults = UserDefaults.standard
        appearance = defaults.string(forKey: "appearance") ?? "system"
        diffStyle = defaults.string(forKey: "diffStyle") ?? "inline"
        lineNumbers = defaults.object(forKey: "lineNumbers") as? Bool ?? true
        accent = ProjectColor(rawValue: defaults.string(forKey: "accent") ?? "blue") ?? .blue
        provider = AIProvider(rawValue: defaults.string(forKey: "provider") ?? "apple") ?? .apple
        models = defaults.dictionary(forKey: "models") as? [String: String] ?? [:]
        instruction = defaults.string(forKey: "commitInstruction") ?? "Use an imperative summary. Keep it under 72 characters. Explain the reason for the change in the description."
        layout = defaults.data(forKey: "layoutOptions").flatMap { try? JSONDecoder().decode(AppearanceOptions.self, from: $0) } ?? AppearanceOptions()
    }
    var model: String {
        get { models[provider.rawValue] ?? provider.defaultModel }
        set { models[provider.rawValue] = newValue }
    }
    func updateDockIcon() {
        NSApplication.shared.applicationIconImage = AppIconRenderer.image
    }
    func resetAppearance() {
        appearance = "system"
        accent = .blue
        layout = AppearanceOptions()
        diffStyle = "inline"
        lineNumbers = true
    }
}

enum AppIconRenderer {
    static var image: NSImage {
        if let url = Bundle.main.url(forResource: "Silver", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(size: .zero)
    }
}
