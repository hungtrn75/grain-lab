import CoreImage
import AppKit

/// Shared by the render pipeline and the red mask overlay.
enum LayerMaskRenderer {
    static func mask(for layer: AdjustmentLayer, extent: CGRect) -> CIImage {
        func pixel(_ point: CGPoint) -> CGPoint {
            CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + (1 - point.y) * extent.height)
        }
        let white = CIColor(red: 1, green: 1, blue: 1)
        let black = CIColor(red: 0, green: 0, blue: 0)
        var mask: CIImage
        switch layer.kind {
        case .linear:
            let start = pixel(layer.start), end = pixel(layer.end)
            if hypot(start.x - end.x, start.y - end.y) < 0.01 {
                mask = CIImage(color: black).cropped(to: extent)
            } else {
                mask = CIFilter(name: "CILinearGradient", parameters: [
                    "inputPoint0": CIVector(cgPoint: start), "inputPoint1": CIVector(cgPoint: end),
                    "inputColor0": white, "inputColor1": black
                ])!.outputImage!.cropped(to: extent)
            }
        case .radial:
            let center = pixel(layer.start)
            let rx = max(abs(layer.end.x - layer.start.x) * extent.width, 1)
            let ry = max(abs(layer.end.y - layer.start.y) * extent.height, 1)
            let radial = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 1 - min(max(layer.feather, 0.01), 1),
                "inputRadius1": 1, "inputColor0": white, "inputColor1": black
            ])!.outputImage!
            mask = radial.transformed(by: CGAffineTransform(scaleX: rx, y: ry)
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y))).cropped(to: extent)
        case .brush:
            mask = brushMask(layer.strokes, extent: extent)
        }
        if layer.inverted { mask = mask.applyingFilter("CIColorInvert") }
        let opacity = min(max(layer.opacity, 0), 1)
        return mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: opacity, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: opacity, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: opacity, w: 0)
        ]).cropped(to: extent)
    }

    private static func brushMask(_ strokes: [BrushStroke], extent: CGRect) -> CIImage {
        let scale = min(1, 1536 / max(extent.width, extent.height))
        let width = max(1, Int(ceil(extent.width * scale)))
        let height = max(1, Int(ceil(extent.height * scale)))
        let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return CIImage(color: .black).cropped(to: extent)
        }
        for stroke in strokes {
            guard !Task.isCancelled else { break }
            let radius = max(0.5, min(max(stroke.radius, 0.001), 0.5) * CGFloat(min(width, height)))
            let hardness = min(max(stroke.hardness, 0), 0.99)
            let flow = min(max(stroke.flow, 0), 1)
            let colors = [CGColor(gray: 1, alpha: flow), CGColor(gray: 1, alpha: flow), CGColor(gray: 1, alpha: 0)] as CFArray
            guard let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, hardness, 1]) else { continue }
            context.setBlendMode(stroke.erase ? .destinationOut : .normal)
            func stamp(_ point: CGPoint) {
                let p = CGPoint(x: point.x * CGFloat(width), y: (1 - point.y) * CGFloat(height))
                context.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
            }
            if let first = stroke.points.first { stamp(first) }
            for (a, b) in zip(stroke.points, stroke.points.dropFirst()) {
                let distance = hypot((a.x - b.x) * CGFloat(width), (a.y - b.y) * CGFloat(height))
                let count = max(1, Int(ceil(distance / max(0.5, radius * 0.25))))
                for index in 1...count {
                    let t = CGFloat(index) / CGFloat(count)
                    stamp(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
        }
        guard let cgImage = context.makeImage() else { return CIImage(color: .black).cropped(to: extent) }
        return CIImage(cgImage: cgImage).composited(over: CIImage(color: .black))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height))
                .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY)))
            .cropped(to: extent)
    }
}
