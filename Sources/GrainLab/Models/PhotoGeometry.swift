import CoreImage

/// Per-photo geometry, independent of reusable color presets. Crop uses bottom-left coordinates.
public struct PhotoGeometry: Equatable {
    public var quarterTurns: Int = 0
    public var straighten: CGFloat = 0
    public var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    public init() {}

    public func apply(to source: CIImage) -> CIImage {
        var image = source
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns != 0 {
            image = image.oriented(forExifOrientation: [1, 6, 3, 8][turns])
        }
        let angle = min(max(straighten.isFinite ? straighten : 0, -15), 15) * .pi / 180
        if abs(angle) > 0.00001 {
            let extent = image.extent
            // Enlarge before rotating so the original frame has no transparent corners.
            let c = abs(cos(angle)), s = abs(sin(angle))
            let scale = max(c + extent.height / extent.width * s,
                            c + extent.width / extent.height * s)
            let transform = CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY))
            image = image.transformed(by: transform).cropped(to: extent)
        }
        let normalized = crop.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        if !normalized.isNull, normalized.width > 0, normalized.height > 0 {
            let extent = image.extent
            let rect = CGRect(x: extent.minX + normalized.minX * extent.width,
                              y: extent.minY + normalized.minY * extent.height,
                              width: normalized.width * extent.width,
                              height: normalized.height * extent.height).integral.intersection(extent)
            if rect.width >= 1, rect.height >= 1 { image = image.cropped(to: rect) }
        }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
