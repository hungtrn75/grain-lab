import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import ImageIO

public struct ImageMetadata {
    public let width: Int
    public let height: Int
    public let cameraMake: String?
    public let cameraModel: String?
    public let iso: Int?
    public let shutterSpeed: String?
    public let aperture: String?
    public let focalLength: String?
    public let lensModel: String?
    public let isRAW: Bool
}

/// The core GPU-accelerated image processing engine for GrainLab.
/// Manages CIRAWFilter, Metal-backed CIContext, and the 5-stage film simulation pipeline.
public final class CoreImageEngine: @unchecked Sendable {
    // Metal-backed CIContext forcing GPU execution
    private let context: CIContext
    private var rawFilter: CIRAWFilter?
    private var originalRawImage: CIImage?
    private var loadedURL: URL?
    private(set) public var currentMetadata: ImageMetadata?
    
    public init() {
        if let device = MTLCreateSystemDefaultDevice() {
            self.context = CIContext(mtlDevice: device, options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        } else {
            self.context = CIContext(options: [
                .useSoftwareRenderer: false,
                .cacheIntermediates: false
            ])
        }
    }
    
    // MARK: - 1. Load RAW / Image File
    /// Loads a RAW file (.NEF, .CR2, .CR3, .ARW, .DNG, .RAF, etc.) or a standard image (.JPG, .PNG, .TIFF).
    public func loadRAW(url: URL) throws {
        self.loadedURL = url
        self.currentMetadata = Self.extractMetadata(from: url)
        
        // Attempt to load using CIRAWFilter first
        if let filter = CIRAWFilter(imageURL: url) {
            self.rawFilter = filter
            // Obtain default output image
            self.originalRawImage = filter.outputImage
        } else {
            // Fallback to standard CIImage loader (for standard JPEG, PNG, TIFF, DNG)
            self.rawFilter = nil
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw EngineError.failedToLoadImage(url)
            }
            self.originalRawImage = image
        }
    }
    
    /// Loads an in-memory CIImage directly (useful for previews and tests)
    public func loadDirect(image: CIImage, metadata: ImageMetadata? = nil) {
        self.rawFilter = nil
        self.loadedURL = nil
        self.originalRawImage = image
        self.currentMetadata = metadata ?? ImageMetadata(
            width: Int(image.extent.width),
            height: Int(image.extent.height),
            cameraMake: nil,
            cameraModel: nil,
            iso: nil,
            shutterSpeed: nil,
            aperture: nil,
            focalLength: nil,
            lensModel: nil,
            isRAW: false
        )
    }
    
    // MARK: - 2. Pipeline Rendering
    /// Renders the current image using the specified film preset.
    /// Follows the mandatory pipeline:
    /// 1. RAW adjustments / WB / Exposure
    /// 2. Tone / Highlights & Shadows
    /// 3. Tone Curve (CIToneCurve)
    /// 4. 3D LUT (CIColorCube)
    /// 5. Film Grain (Noise + Soft Light Composite)
    public func render(with preset: FilmPreset) -> CGImage? {
        return render(with: preset, targetMaxDimension: nil)
    }
    
    /// Renders with an optional downsampling target size for high-performance interactive previewing
    public func render(with preset: FilmPreset, targetMaxDimension: CGFloat? = nil) -> CGImage? {
        guard var currentImage = getBaseImage(for: preset) else { return nil }
        
        // Downsample for preview if requested
        if let maxDim = targetMaxDimension, maxDim > 0 {
            let width = currentImage.extent.width
            let height = currentImage.extent.height
            let currentMax = max(width, height)
            if currentMax > maxDim {
                let scale = maxDim / currentMax
                currentImage = currentImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        
        // Step 1 & 2: Tone Adjustments (Exposure, Contrast, Highlights, Shadows, WB if non-RAW)
        currentImage = applyToneAdjustments(to: currentImage, preset: preset)
        
        // Step 3: Tone Curve (CIToneCurve)
        currentImage = applyToneCurve(to: currentImage, preset: preset)
        
        // Step 4: 3D LUT (CIColorCube)
        currentImage = apply3DLUT(to: currentImage, preset: preset)
        
        // Step 5: Film Grain (Noise + Soft Light Blend)
        currentImage = applyFilmGrain(to: currentImage, preset: preset)
        
        // Step 6: Render to CGImage on GPU in standard sRGB color space
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return context.createCGImage(currentImage, from: currentImage.extent, format: .RGBA8, colorSpace: srgb)
    }
    
    // MARK: - Pipeline Steps
    
    /// Prepares base CIImage, applying RAW-level adjustments if using CIRAWFilter
    private func getBaseImage(for preset: FilmPreset) -> CIImage? {
        if let raw = self.rawFilter {
            // Apply demosaicing parameters directly to CIRAWFilter
            raw.exposure = Float(preset.exposure)
            raw.neutralTemperature = Float(preset.temperature)
            raw.neutralTint = Float(preset.tint)
            return raw.outputImage ?? originalRawImage
        }
        return originalRawImage
    }
    
    /// Applies exposure, white balance (for non-RAW), contrast, and highlight/shadow recovery
    private func applyToneAdjustments(to image: CIImage, preset: FilmPreset) -> CIImage {
        var output = image
        
        // If not processed at RAW demosaic level, apply WB via CITemperatureAndTint
        if self.rawFilter == nil {
            if abs(preset.temperature - 5500.0) > 1.0 || abs(preset.tint) > 0.5 {
                if let tempFilter = CIFilter(name: "CITemperatureAndTint") {
                    tempFilter.setValue(output, forKey: kCIInputImageKey)
                    tempFilter.setValue(CIVector(x: 5500, y: 0), forKey: "inputNeutral")
                    tempFilter.setValue(CIVector(x: preset.temperature, y: preset.tint), forKey: "inputTargetNeutral")
                    if let result = tempFilter.outputImage {
                        output = result
                    }
                }
            }
            
            // Exposure adjustment
            if abs(preset.exposure) > 0.001 {
                if let expFilter = CIFilter(name: "CIExposureAdjust") {
                    expFilter.setValue(output, forKey: kCIInputImageKey)
                    expFilter.setValue(preset.exposure, forKey: "inputEV")
                    if let result = expFilter.outputImage {
                        output = result
                    }
                }
            }
        }
        
        // Highlight & Shadow Recovery
        if abs(preset.shadows) > 0.001 || abs(preset.highlights) > 0.001 {
            if let hlFilter = CIFilter(name: "CIHighlightShadowAdjust") {
                hlFilter.setValue(output, forKey: kCIInputImageKey)
                // Highlights: 1.0 is neutral, < 1.0 compresses highlights
                hlFilter.setValue(1.0 - preset.highlights, forKey: "inputHighlightAmount")
                // Shadows: 0.0 is neutral, positive opens shadows
                hlFilter.setValue(preset.shadows, forKey: "inputShadowAmount")
                if let result = hlFilter.outputImage {
                    output = result
                }
            }
        }
        
        // Contrast
        if abs(preset.contrast - 1.0) > 0.001 {
            if let colorControls = CIFilter(name: "CIColorControls") {
                colorControls.setValue(output, forKey: kCIInputImageKey)
                colorControls.setValue(preset.contrast, forKey: kCIInputContrastKey)
                if let result = colorControls.outputImage {
                    output = result
                }
            }
        }
        
        return output
    }
    
    /// Applies 5-point Tone Curve (CIToneCurve)
    private func applyToneCurve(to image: CIImage, preset: FilmPreset) -> CIImage {
        guard let curveFilter = CIFilter(name: "CIToneCurve") else { return image }
        
        let (p0, p1, p2, p3, p4) = preset.normalized5Points
        
        // If identity linear curve, skip to save GPU cycles
        let isLinear = (p0.y == 0.0 && p1.y == 0.25 && p2.y == 0.50 && p3.y == 0.75 && p4.y == 1.00)
        if isLinear { return image }
        
        curveFilter.setValue(image, forKey: kCIInputImageKey)
        curveFilter.setValue(CIVector(cgPoint: p0), forKey: "inputPoint0")
        curveFilter.setValue(CIVector(cgPoint: p1), forKey: "inputPoint1")
        curveFilter.setValue(CIVector(cgPoint: p2), forKey: "inputPoint2")
        curveFilter.setValue(CIVector(cgPoint: p3), forKey: "inputPoint3")
        curveFilter.setValue(CIVector(cgPoint: p4), forKey: "inputPoint4")
        
        return curveFilter.outputImage ?? image
    }
    
    /// Applies 3D LUT (CIColorCube) parsed from .cube file with intensity control
    private func apply3DLUT(to image: CIImage, preset: FilmPreset) -> CIImage {
        guard let lutName = preset.lutFileName, !lutName.isEmpty, preset.lutIntensity > 0.001 else {
            return image
        }
        
        guard let lutURL = LUTRegistry.shared.resolveURL(for: lutName) else {
            return image
        }
        
        do {
            let lutData = try LUTParser.shared.parse(from: lutURL)
            let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            
            // Prefer CIColorCubeWithColorSpace so Core Image transforms pixels to sRGB
            // before sampling the .cube 3D LUT, avoiding linear-gamma color/yellow distortion
            let cubeFilter: CIFilter
            if let filterWithSpace = CIFilter(name: "CIColorCubeWithColorSpace") {
                filterWithSpace.setValue(srgb, forKey: "inputColorSpace")
                cubeFilter = filterWithSpace
            } else if let standardFilter = CIFilter(name: "CIColorCube") {
                cubeFilter = standardFilter
            } else {
                return image
            }
            
            cubeFilter.setValue(image, forKey: kCIInputImageKey)
            cubeFilter.setValue(lutData.dimension, forKey: "inputCubeDimension")
            cubeFilter.setValue(lutData.data, forKey: "inputCubeData")
            
            guard let lutOutput = cubeFilter.outputImage else { return image }
            
            // If intensity is 1.0, return directly
            if preset.lutIntensity >= 0.999 {
                return lutOutput
            }
            
            // Blend between original and LUT output using CIBlendWithMask
            let maskColor = CIColor(red: preset.lutIntensity, green: preset.lutIntensity, blue: preset.lutIntensity)
            let mask = CIImage(color: maskColor).cropped(to: image.extent)
            
            if let blendFilter = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: lutOutput,
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ]) {
                return blendFilter.outputImage ?? lutOutput
            }
            
            return lutOutput
        } catch {
            print("[CoreImageEngine] Failed to apply LUT: \(error)")
            return image
        }
    }
    
    /// Generates custom film grain noise and composites it onto the image
    private func applyFilmGrain(to image: CIImage, preset: FilmPreset) -> CIImage {
        guard preset.grainIntensity > 0.005 else { return image }
        
        guard let randomFilter = CIFilter(name: "CIRandomGenerator") else { return image }
        guard let rawNoise = randomFilter.outputImage else { return image }
        
        // 1. Desaturate noise to make it monochrome film grain
        let monoNoise = rawNoise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0,
            kCIInputBrightnessKey: 0.0,
            // Modulate noise contrast based on grain intensity
            kCIInputContrastKey: 1.0 + (preset.grainIntensity * 1.5)
        ])
        
        // 2. Scale noise according to grainSize
        let size = max(preset.grainSize, 1.0)
        let scaledNoise = monoNoise
            .transformed(by: CGAffineTransform(scaleX: size, y: size))
            .cropped(to: image.extent)
        
        // 3. Composite using Soft Light blend mode (ideal photographic film grain response)
        guard let softLight = CIFilter(name: "CISoftLightBlendMode", parameters: [
            kCIInputImageKey: scaledNoise,
            kCIInputBackgroundImageKey: image
        ])?.outputImage else {
            return image
        }
        
        // 4. Modulate blend intensity with mask
        let mask = CIImage(color: CIColor(
            red: preset.grainIntensity,
            green: preset.grainIntensity,
            blue: preset.grainIntensity
        )).cropped(to: image.extent)
        
        if let finalGrain = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: softLight,
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: mask
        ])?.outputImage {
            return finalGrain
        }
        
        return softLight
    }
    
    // MARK: - Metadata Extraction
    private static func extractMetadata(from url: URL) -> ImageMetadata {
        let isRawExt = ["nef", "cr2", "cr3", "arw", "dng", "raf", "rw2", "orf", "pef"]
            .contains(url.pathExtension.lowercased())
        
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImageMetadata(
                width: 0,
                height: 0,
                cameraMake: nil,
                cameraModel: nil,
                iso: nil,
                shutterSpeed: nil,
                aperture: nil,
                focalLength: nil,
                lensModel: nil,
                isRAW: isRawExt
            )
        }
        
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        
        let make = tiff?[kCGImagePropertyTIFFMake] as? String
        let model = tiff?[kCGImagePropertyTIFFModel] as? String
        
        var isoVal: Int? = nil
        if let isos = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = isos.first {
            isoVal = first
        }
        
        var shutterStr: String? = nil
        if let expTime = exif?[kCGImagePropertyExifExposureTime] as? Double {
            if expTime < 1.0 && expTime > 0.0 {
                shutterStr = "1/\(Int(round(1.0 / expTime)))s"
            } else {
                shutterStr = String(format: "%.1fs", expTime)
            }
        }
        
        var apertureStr: String? = nil
        if let fNumber = exif?[kCGImagePropertyExifFNumber] as? Double {
            apertureStr = String(format: "ƒ/%.1f", fNumber)
        }
        
        var focalLengthStr: String? = nil
        if let fl = exif?[kCGImagePropertyExifFocalLength] as? Double {
            focalLengthStr = "\(Int(round(fl)))mm"
        }
        
        let lens = exif?[kCGImagePropertyExifLensModel] as? String
        
        return ImageMetadata(
            width: width,
            height: height,
            cameraMake: make,
            cameraModel: model,
            iso: isoVal,
            shutterSpeed: shutterStr,
            aperture: apertureStr,
            focalLength: focalLengthStr,
            lensModel: lens,
            isRAW: isRawExt
        )
    }
}

public enum EngineError: LocalizedError {
    case failedToLoadImage(URL)
    case renderingFailed
    
    public var errorDescription: String? {
        switch self {
        case .failedToLoadImage(let url):
            return "Failed to read or decode image at \(url.path)"
        case .renderingFailed:
            return "Failed to render processed image"
        }
    }
}
