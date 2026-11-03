import Foundation
import CoreGraphics

public enum LayerMaskKind: String, Codable, CaseIterable, Identifiable {
    case linear = "Linear Gradient", radial = "Radial Gradient", brush = "Brush"
    public var id: String { rawValue }
}

/// Points/radii are normalized in the original oriented source, not the viewport.
public struct BrushStroke: Codable, Equatable {
    public var points: [CGPoint]
    public var radius: CGFloat
    public var hardness: CGFloat
    public var flow: CGFloat
    public var erase: Bool
}

public struct AdjustmentLayer: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var kind: LayerMaskKind
    public var enabled = true
    public var opacity: CGFloat = 1
    public var inverted = false
    public var start = CGPoint(x: 0.5, y: 0.25)
    public var end = CGPoint(x: 0.5, y: 0.75)
    public var feather: CGFloat = 0.5
    public var strokes: [BrushStroke] = []
    public var exposure: CGFloat = 0
    public var contrast: CGFloat = 1
    public var saturation: CGFloat = 1
    public var warmth: CGFloat = 0

    public init(kind: LayerMaskKind, name: String? = nil) {
        self.kind = kind
        self.name = name ?? kind.rawValue
        if kind == .radial {
            start = CGPoint(x: 0.5, y: 0.5)
            end = CGPoint(x: 0.75, y: 0.75)
        }
    }
}

struct LayerArchive: Codable {
    var version = 1
    var layers: [AdjustmentLayer]

    static func decode(_ data: Data) throws -> [AdjustmentLayer] {
        let archive = try JSONDecoder().decode(LayerArchive.self, from: data)
        func point(_ point: CGPoint) -> Bool { (0...1).contains(point.x) && (0...1).contains(point.y) }
        guard archive.version == 1, archive.layers.count <= 128 else { throw LayerArchiveError.invalid }
        for layer in archive.layers {
            guard point(layer.start), point(layer.end), (0...1).contains(layer.opacity), (0.01...1).contains(layer.feather),
                  (-3...3).contains(layer.exposure), (0.5...2).contains(layer.contrast), (0...2).contains(layer.saturation),
                  (-2500...2500).contains(layer.warmth), layer.strokes.count <= 2000 else { throw LayerArchiveError.invalid }
            for stroke in layer.strokes {
                guard (0.001...0.5).contains(stroke.radius), (0...1).contains(stroke.hardness), (0...1).contains(stroke.flow),
                      stroke.points.count <= 100000, stroke.points.allSatisfy(point) else { throw LayerArchiveError.invalid }
            }
        }
        return archive.layers
    }
}

enum LayerArchiveError: LocalizedError {
    case invalid
    var errorDescription: String? { "Unsupported or invalid layer file." }
}
