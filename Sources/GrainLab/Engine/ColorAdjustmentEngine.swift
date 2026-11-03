import Foundation

/// Display-referred HSL adjustment baked into an sRGB cube, shared by preview and export.
final class ColorAdjustmentEngine {
    static let shared = ColorAdjustmentEngine()
    private let cache = NSCache<NSData, NSData>()
    private let dimension = 33
    init() { cache.totalCostLimit = 16 * 1024 * 1024 }

    func cube(for settings: ColorAdjustments) -> LUTData? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard settings.isAdjusted, let key = try? encoder.encode(settings) else { return nil }
        if let data = cache.object(forKey: key as NSData) { return LUTData(dimension: dimension, data: data as Data) }
        let ranges = settings.ranges.filter(\.isAdjusted)
        var floats: [Float] = []
        floats.reserveCapacity(dimension * dimension * dimension * 4)
        for blue in 0..<dimension {
            guard !Task.isCancelled else { return nil }
            for green in 0..<dimension {
                for red in 0..<dimension {
                    let input = SIMD3<Float>(Float(red) / 32, Float(green) / 32, Float(blue) / 32)
                    let output = Self.adjust(input, ranges: ranges)
                    floats += [output.x, output.y, output.z, 1]
                }
            }
        }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(data as NSData, forKey: key as NSData, cost: data.count)
        return LUTData(dimension: dimension, data: data)
    }

    static func hsl(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let maxValue = max(rgb.x, max(rgb.y, rgb.z)), minValue = min(rgb.x, min(rgb.y, rgb.z))
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2
        guard delta > 0.00001 else { return SIMD3(0, 0, lightness) }
        let saturation = delta / max(0.00001, 1 - abs(2 * lightness - 1))
        var hue: Float
        if maxValue == rgb.x { hue = (rgb.y - rgb.z) / delta }
        else if maxValue == rgb.y { hue = (rgb.z - rgb.x) / delta + 2 }
        else { hue = (rgb.x - rgb.y) / delta + 4 }
        hue /= 6
        if hue < 0 { hue += 1 }
        return SIMD3(hue, saturation, lightness)
    }

    static func rgb(_ hsl: SIMD3<Float>) -> SIMD3<Float> {
        let chroma = (1 - abs(2 * hsl.z - 1)) * hsl.y
        let h = (hsl.x - floor(hsl.x)) * 6
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let value: SIMD3<Float>
        switch h {
        case ..<1: value = SIMD3(chroma, x, 0)
        case ..<2: value = SIMD3(x, chroma, 0)
        case ..<3: value = SIMD3(0, chroma, x)
        case ..<4: value = SIMD3(0, x, chroma)
        case ..<5: value = SIMD3(x, 0, chroma)
        default: value = SIMD3(chroma, 0, x)
        }
        return value + SIMD3(repeating: hsl.z - chroma / 2)
    }

    static func weight(hue: Float, saturation: Float, range: ColorRangeAdjustment) -> Float {
        guard range.enabled, range.center.isFinite, range.width.isFinite, range.softness.isFinite else { return 0 }
        let center = Float(range.center / 360)
        let raw = abs(hue - center).truncatingRemainder(dividingBy: 1)
        let distance = min(raw, 1 - raw) * 360
        let outer = min(max(Float(range.width), 1), 180)
        let inner = outer * (1 - min(max(Float(range.softness), 0.01), 1))
        let t = min(max((distance - inner) / max(outer - inner, 0.001), 0), 1)
        // Fade out near neutrals to avoid assigning arbitrary hues to gray pixels.
        let neutral = min(max((saturation - 0.02) / 0.1, 0), 1)
        return (1 - t * t * (3 - 2 * t)) * neutral * neutral * (3 - 2 * neutral)
    }

    static func adjust(_ input: SIMD3<Float>, ranges: [ColorRangeAdjustment]) -> SIMD3<Float> {
        let original = hsl(input)
        var hue: Float = 0, saturation: Float = 0, lightness: Float = 0
        for range in ranges where range.isAdjusted {
            let weight = weight(hue: original.x, saturation: original.y, range: range)
            guard range.hue.isFinite, range.saturation.isFinite, range.lightness.isFinite else { continue }
            hue += min(max(Float(range.hue), -60), 60) / 360 * weight
            saturation += min(max(Float(range.saturation), -1), 1) * weight
            lightness += min(max(Float(range.lightness), -0.5), 0.5) * weight
        }
        return rgb(SIMD3(original.x + hue, min(max(original.y * (1 + saturation), 0), 1), min(max(original.z + lightness, 0), 1)))
    }
}
