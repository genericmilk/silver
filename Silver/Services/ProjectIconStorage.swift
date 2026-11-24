import AppKit
import SwiftUI

@MainActor enum ProjectIconStorage {
    private static let cache = NSCache<NSString, NSImage>()
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Silver/Project Icons", isDirectory: true)
    }
    static func image(_ filename: String?) -> NSImage? {
        guard let filename, filename == (filename as NSString).lastPathComponent else { return nil }
        if let image = cache.object(forKey: filename as NSString) { return image }
        guard let image = NSImage(contentsOf: directory.appendingPathComponent(filename)) else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }
    static func thumbnail(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 25_000_000, let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            throw GitFailure("Choose an image smaller than 25 MB.")
        }
        let size: CGFloat = 256
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 256, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw GitFailure("Unable to prepare the image.") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 40, yRadius: 40).addClip()
        let scale = min(size / image.size.width, size / image.size.height)
        let width = image.size.width * scale, height = image.size.height * scale
        image.draw(in: NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw GitFailure("Unable to read the image.") }
        return png
    }
    static func save(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = UUID().uuidString + ".png"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }
}

struct ProjectIcon: View {
    let project: Project
    var size: CGFloat = 44
    var body: some View {
        AnimatedProjectIcon(symbol: project.symbol, color: project.color, size: size, image: ProjectIconStorage.image(project.iconFile))
            .frame(width: size, height: size)
    }
}
