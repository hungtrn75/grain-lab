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

extension PhotoGeometry {
    /// Same source-to-output mapping as apply(to:), for mask drawing through a crop.
    func mapping(sourceSize: CGSize) -> (transform: CGAffineTransform, size: CGSize) {
        let w = sourceSize.width, h = sourceSize.height
        let turns = ((quarterTurns % 4) + 4) % 4
        var transform: CGAffineTransform
        var size: CGSize
        switch turns {
        case 1: transform = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w); size = CGSize(width: h, height: w)
        case 2: transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h); size = sourceSize
        case 3: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0); size = CGSize(width: h, height: w)
        default: transform = .identity; size = sourceSize
        }
        let angle = min(max(straighten.isFinite ? straighten : 0, -15), 15) * .pi / 180
        if abs(angle) > 0.00001 {
            let c = abs(cos(angle)), s = abs(sin(angle))
            let scale = max(c + size.height / size.width * s, c + size.width / size.height * s)
            transform = transform.concatenating(CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
        }
        let normalized = crop.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        if !normalized.isNull, normalized.width > 0, normalized.height > 0 {
            let rect = CGRect(x: normalized.minX * size.width, y: normalized.minY * size.height,
                              width: normalized.width * size.width, height: normalized.height * size.height)
                .integral.intersection(CGRect(origin: .zero, size: size))
            if rect.width >= 1, rect.height >= 1 {
                transform = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
                size = rect.size
            }
        }
        return (transform, size)
    }

    func sourcePoint(fromOutput point: CGPoint, sourceSize: CGSize) -> CGPoint {
        let map = mapping(sourceSize: sourceSize)
        let output = CGPoint(x: point.x * map.size.width, y: (1 - point.y) * map.size.height)
        let source = output.applying(map.transform.inverted())
        return CGPoint(x: source.x / sourceSize.width, y: 1 - source.y / sourceSize.height)
    }

    func outputPoint(fromSource point: CGPoint, sourceSize: CGSize) -> CGPoint {
        let map = mapping(sourceSize: sourceSize)
        let source = CGPoint(x: point.x * sourceSize.width, y: (1 - point.y) * sourceSize.height).applying(map.transform)
        return CGPoint(x: source.x / map.size.width, y: 1 - source.y / map.size.height)
    }
}
