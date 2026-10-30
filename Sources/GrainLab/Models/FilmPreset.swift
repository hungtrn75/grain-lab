import Foundation
import CoreGraphics

/// Model representing the editing state and film simulation parameters of an image.
/// Conforms to Codable for easy JSON / XMP export and import.
public struct FilmPreset: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    
    // MARK: - Basic RAW Adjustments
    /// White balance color temperature in Kelvin (2000K - 10000K)
    public var temperature: CGFloat = 5500.0
    /// White balance tint (-150.0 to 150.0, Green to Magenta)
    public var tint: CGFloat = 0.0
    /// Exposure compensation in EV (-3.0 to 3.0)
    public var exposure: CGFloat = 0.0
    
    // MARK: - Tone & Contrast
    /// Shadow recovery / crush (-1.0 to 1.0)
    public var shadows: CGFloat = 0.0
    /// Highlight recovery / compression (-1.0 to 1.0)
    public var highlights: CGFloat = 0.0
    /// Midtone contrast multiplier (0.5 to 2.0, default 1.0)
    public var contrast: CGFloat = 1.0
    
    // MARK: - Film Simulation Specifics
    /// Control points for the tone curve (normalized 0.0...1.0)
    /// Expects 5 points for CIToneCurve [black, shadow, midtone, highlight, white]
    public var toneCurvePoints: [CGPoint] = [
        CGPoint(x: 0.0, y: 0.0),
        CGPoint(x: 0.25, y: 0.25),
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.75, y: 0.75),
        CGPoint(x: 1.0, y: 1.0)
    ]
    
    /// Optional .cube LUT file name located in bundle or user documents
    public var lutFileName: String? = nil
    /// Intensity / opacity of the 3D LUT (0.0 to 1.0)
    public var lutIntensity: CGFloat = 1.0
    
    // MARK: - Effects
    /// Film grain noise intensity (0.0 to 1.0)
    public var grainIntensity: CGFloat = 0.0
    /// Film grain noise particle size (1.0 to 3.0)
    public var grainSize: CGFloat = 1.0
    
    // MARK: - Initializer
    public init(
        id: UUID = UUID(),
        name: String = "Default",
        temperature: CGFloat = 5500.0,
        tint: CGFloat = 0.0,
        exposure: CGFloat = 0.0,
        shadows: CGFloat = 0.0,
        highlights: CGFloat = 0.0,
        contrast: CGFloat = 1.0,
        toneCurvePoints: [CGPoint] = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 0.25, y: 0.25),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.75, y: 0.75),
            CGPoint(x: 1.0, y: 1.0)
        ],
        lutFileName: String? = nil,
        lutIntensity: CGFloat = 1.0,
        grainIntensity: CGFloat = 0.0,
        grainSize: CGFloat = 1.0
    ) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.tint = tint
        self.exposure = exposure
        self.shadows = shadows
        self.highlights = highlights
        self.contrast = contrast
        self.toneCurvePoints = toneCurvePoints
        self.lutFileName = lutFileName
        self.lutIntensity = lutIntensity
        self.grainIntensity = grainIntensity
        self.grainSize = grainSize
    }
}

// MARK: - Curve Helpers
extension FilmPreset {
    /// Always returns exactly 5 points required by CIToneCurve
    public var normalized5Points: (CGPoint, CGPoint, CGPoint, CGPoint, CGPoint) {
        if toneCurvePoints.count >= 5 {
            return (
                toneCurvePoints[0],
                toneCurvePoints[1],
                toneCurvePoints[2],
                toneCurvePoints[3],
                toneCurvePoints[4]
            )
        } else if toneCurvePoints.count == 2 {
            // Linear interpolation between the two endpoints
            let p0 = toneCurvePoints[0]
            let p4 = toneCurvePoints[1]
            let p1 = CGPoint(x: p0.x + (p4.x - p0.x) * 0.25, y: p0.y + (p4.y - p0.y) * 0.25)
            let p2 = CGPoint(x: p0.x + (p4.x - p0.x) * 0.50, y: p0.y + (p4.y - p0.y) * 0.50)
            let p3 = CGPoint(x: p0.x + (p4.x - p0.x) * 0.75, y: p0.y + (p4.y - p0.y) * 0.75)
            return (p0, p1, p2, p3, p4)
        } else {
            return (
                CGPoint(x: 0.0, y: 0.0),
                CGPoint(x: 0.25, y: 0.25),
                CGPoint(x: 0.5, y: 0.5),
                CGPoint(x: 0.75, y: 0.75),
                CGPoint(x: 1.0, y: 1.0)
            )
        }
    }
}

// MARK: - Built-in Presets
extension FilmPreset {
    public static let defaultPreset = FilmPreset(
        name: "Default (Neutral)",
        temperature: 5500,
        tint: 0,
        exposure: 0,
        shadows: 0,
        highlights: 0,
        contrast: 1.0,
        grainIntensity: 0.0,
        grainSize: 1.0
    )
    
    public static let kodakPortra400 = FilmPreset(
        name: "Kodak Portra 400",
        temperature: 5800,
        tint: 4.0,
        exposure: 0.15,
        shadows: 0.15,
        highlights: -0.10,
        contrast: 1.08,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.02),
            CGPoint(x: 0.25, y: 0.23),
            CGPoint(x: 0.50, y: 0.51),
            CGPoint(x: 0.75, y: 0.78),
            CGPoint(x: 1.00, y: 0.98)
        ],
        lutFileName: "Kodak_Portra_400.cube",
        lutIntensity: 0.85,
        grainIntensity: 0.22,
        grainSize: 1.3
    )
    
    public static let fujiPro400H = FilmPreset(
        name: "Fujifilm Pro 400H",
        temperature: 5200,
        tint: -5.0,
        exposure: 0.20,
        shadows: 0.25,
        highlights: -0.15,
        contrast: 0.98,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.04),
            CGPoint(x: 0.25, y: 0.27),
            CGPoint(x: 0.50, y: 0.52),
            CGPoint(x: 0.75, y: 0.76),
            CGPoint(x: 1.00, y: 0.96)
        ],
        lutFileName: "Fuji_Pro_400H.cube",
        lutIntensity: 0.90,
        grainIntensity: 0.20,
        grainSize: 1.2
    )
    
    public static let ilfordHP5 = FilmPreset(
        name: "Ilford HP5 Plus (B&W)",
        temperature: 5500,
        tint: 0.0,
        exposure: 0.0,
        shadows: -0.10,
        highlights: 0.10,
        contrast: 1.25,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.00),
            CGPoint(x: 0.25, y: 0.20),
            CGPoint(x: 0.50, y: 0.50),
            CGPoint(x: 0.75, y: 0.82),
            CGPoint(x: 1.00, y: 1.00)
        ],
        lutFileName: "Ilford_HP5_Plus.cube",
        lutIntensity: 1.0,
        grainIntensity: 0.45,
        grainSize: 1.8
    )
    
    public static let cinestill800T = FilmPreset(
        name: "CineStill 800T",
        temperature: 4100,
        tint: 8.0,
        exposure: 0.05,
        shadows: 0.20,
        highlights: -0.05,
        contrast: 1.15,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.05),
            CGPoint(x: 0.25, y: 0.22),
            CGPoint(x: 0.50, y: 0.50),
            CGPoint(x: 0.75, y: 0.80),
            CGPoint(x: 1.00, y: 0.99)
        ],
        lutFileName: "Cinestill_800T.cube",
        lutIntensity: 0.88,
        grainIntensity: 0.35,
        grainSize: 1.5
    )
    
    public static let kodachrome64 = FilmPreset(
        name: "Kodachrome 64 Vintage",
        temperature: 5650,
        tint: 2.0,
        exposure: -0.1,
        shadows: -0.2,
        highlights: 0.05,
        contrast: 1.3,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.00),
            CGPoint(x: 0.25, y: 0.18),
            CGPoint(x: 0.50, y: 0.50),
            CGPoint(x: 0.75, y: 0.85),
            CGPoint(x: 1.00, y: 1.00)
        ],
        lutFileName: "Kodachrome_64.cube",
        lutIntensity: 0.95,
        grainIntensity: 0.28,
        grainSize: 1.4
    )
    
    public static let kodakColorPro = FilmPreset(
        name: "Kodak Color Pro",
        temperature: 5600,
        tint: 2.0,
        exposure: 0.1,
        shadows: 0.12,
        highlights: -0.05,
        contrast: 1.10,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.02),
            CGPoint(x: 0.25, y: 0.22),
            CGPoint(x: 0.50, y: 0.50),
            CGPoint(x: 0.75, y: 0.80),
            CGPoint(x: 1.00, y: 0.99)
        ],
        lutFileName: "Presetpro_Kodak_Color.cube",
        lutIntensity: 1.0,
        grainIntensity: 0.24,
        grainSize: 1.2
    )
    
    public static let kodakGold200 = FilmPreset(
        name: "Kodak Gold 200",
        temperature: 5850,
        tint: 3.0,
        exposure: 0.15,
        shadows: 0.10,
        highlights: -0.08,
        contrast: 1.12,
        toneCurvePoints: [
            CGPoint(x: 0.00, y: 0.03),
            CGPoint(x: 0.25, y: 0.23),
            CGPoint(x: 0.50, y: 0.51),
            CGPoint(x: 0.75, y: 0.79),
            CGPoint(x: 1.00, y: 0.98)
        ],
        lutFileName: "Kodak_Gold_200.cube",
        lutIntensity: 0.95,
        grainIntensity: 0.30,
        grainSize: 1.3
    )
    
    public static let builtInPresets: [FilmPreset] = [
        defaultPreset,
        kodakPortra400,
        kodakGold200,
        kodakColorPro,
        fujiPro400H,
        ilfordHP5,
        cinestill800T,
        kodachrome64
    ]
}
