import Foundation
import CoreGraphics

public struct ColorRangeAdjustment: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var center: CGFloat
    /// Hue distance from the center, in degrees.
    public var width: CGFloat = 35
    public var softness: CGFloat = 0.5
    public var hue: CGFloat = 0
    public var saturation: CGFloat = 0
    public var lightness: CGFloat = 0
    public var enabled = true
    public var isAdjusted: Bool { enabled && (hue != 0 || saturation != 0 || lightness != 0) }

    public init(name: String, center: CGFloat) { self.name = name; self.center = center }
}

public struct ColorAdjustments: Codable, Equatable {
    public var enabled = true
    public var ranges: [ColorRangeAdjustment] = [
        ColorRangeAdjustment(name: "Red", center: 0), ColorRangeAdjustment(name: "Orange", center: 30),
        ColorRangeAdjustment(name: "Yellow", center: 60), ColorRangeAdjustment(name: "Green", center: 120),
        ColorRangeAdjustment(name: "Cyan", center: 180), ColorRangeAdjustment(name: "Blue", center: 240),
        ColorRangeAdjustment(name: "Purple", center: 270), ColorRangeAdjustment(name: "Magenta", center: 300)
    ]
    public init() {}
    public var isAdjusted: Bool { enabled && ranges.contains(where: \.isAdjusted) }
}
