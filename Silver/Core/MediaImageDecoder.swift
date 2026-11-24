import Foundation
import ImageIO

public struct MediaImageFrame: @unchecked Sendable {
    public let image: CGImage
    public let width: Int
    public let height: Int
}

public enum MediaImageDecoder {
    public static func decode(_ data: Data) throws -> MediaImageFrame {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw GitFailure("macOS could not read this image format.") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        if (5...8).contains(orientation) { swap(&width, &height) }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 4_096, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw GitFailure("macOS could not decode this image.") }
        return MediaImageFrame(image: thumbnail, width: width, height: height)
    }
}
