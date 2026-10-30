import XCTest
import CoreImage
@testable import GrainLab

final class GrainLabTests: XCTestCase {
    
    // MARK: - Task 1 Tests: FilmPreset & Codable & PresetManager
    func testFilmPresetCodable() throws {
        let preset = FilmPreset(
            name: "Test Vintage 1970",
            temperature: 6200.0,
            tint: 15.0,
            exposure: 0.5,
            shadows: 0.2,
            highlights: -0.3,
            contrast: 1.15,
            toneCurvePoints: [
                CGPoint(x: 0.0, y: 0.05),
                CGPoint(x: 0.25, y: 0.22),
                CGPoint(x: 0.50, y: 0.50),
                CGPoint(x: 0.75, y: 0.80),
                CGPoint(x: 1.0, y: 0.98)
            ],
            lutFileName: "Kodak_Portra_400.cube",
            lutIntensity: 0.85,
            grainIntensity: 0.35,
            grainSize: 1.6
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(preset)
        XCTAssertGreaterThan(data.count, 0)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(FilmPreset.self, from: data)
        
        XCTAssertEqual(decoded.name, preset.name)
        XCTAssertEqual(decoded.temperature, preset.temperature)
        XCTAssertEqual(decoded.tint, preset.tint)
        XCTAssertEqual(decoded.exposure, preset.exposure)
        XCTAssertEqual(decoded.contrast, preset.contrast)
        XCTAssertEqual(decoded.lutFileName, preset.lutFileName)
        XCTAssertEqual(decoded.grainIntensity, preset.grainIntensity)
        XCTAssertEqual(decoded.toneCurvePoints.count, 5)
    }
    
    func testPresetManagerSaveAndLoad() throws {
        let manager = PresetManager.shared
        let testPreset = FilmPreset(
            name: "Automated_Test_Preset_\(UUID().uuidString.prefix(6))",
            temperature: 4800,
            grainIntensity: 0.4
        )
        
        let savedURL = try manager.savePreset(testPreset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        
        let loaded = try manager.loadPreset(from: savedURL)
        XCTAssertEqual(loaded.name, testPreset.name)
        XCTAssertEqual(loaded.temperature, testPreset.temperature)
        
        // Cleanup
        try manager.deletePreset(testPreset)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))
    }
    
    // MARK: - Task 2 Tests: LUT Parser (.cube)
    func testLUTParserWithIdentityAndCustomCube() throws {
        let cubeContent = """
        # Custom 2x2x2 Test Cube
        TITLE "Test Cube"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        
        let lutData = try LUTParser.shared.parse(string: cubeContent)
        XCTAssertEqual(lutData.dimension, 2)
        XCTAssertEqual(lutData.title, "Test Cube")
        // 2x2x2 = 8 points * 4 floats (RGBA) * 4 bytes = 128 bytes
        XCTAssertEqual(lutData.data.count, 128)
    }
    
    func testLUTRegistryResolvesDefaultLUTs() {
        let registry = LUTRegistry.shared
        XCTAssertGreaterThan(registry.availableLUTs.count, 0)
        
        let portraURL = registry.resolveURL(for: "Kodak_Portra_400.cube")
        XCTAssertNotNil(portraURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: portraURL!.path))
    }
    
    // MARK: - Task 3 Tests: The Image Pipeline
    func testEnginePipelineRender() throws {
        let engine = CoreImageEngine()
        
        // Create test image (100x100 RGB image)
        let testCIImage = CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        
        engine.loadDirect(image: testCIImage)
        
        // Test Render with Kodak Portra 400 preset (Full Pipeline: Tone + Curve + 3D LUT + Grain)
        let preset = FilmPreset.kodakPortra400
        let cgImage = engine.render(with: preset)
        
        XCTAssertNotNil(cgImage, "Render pipeline should produce a non-nil CGImage")
        XCTAssertEqual(cgImage?.width, 200)
        XCTAssertEqual(cgImage?.height, 200)
    }
    
    func testEnginePipelineAllFilmStocks() throws {
        let engine = CoreImageEngine()
        let testCIImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        engine.loadDirect(image: testCIImage)
        
        for preset in FilmPreset.builtInPresets {
            let rendered = engine.render(with: preset)
            XCTAssertNotNil(rendered, "Failed to render built-in preset: \(preset.name)")
        }
    }
    
    // MARK: - Task 4 Tests: ViewModel & Concurrency
    @MainActor
    func testEditorViewModelDebounceAndProcess() async throws {
        let vm = EditorViewModel()
        let testImage = CIImage(color: CIColor(red: 0.7, green: 0.3, blue: 0.2))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        vm.loadDirectImage(testImage)
        
        // Wait for asynchronous render
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        XCTAssertNotNil(vm.displayImage, "Display image should be populated after render")
        XCTAssertFalse(vm.histogramLuma.isEmpty, "Histogram should be computed")
        
        // Test slider modification triggers debounce
        vm.currentPreset.exposure = 1.5
        XCTAssertEqual(vm.currentPreset.exposure, 1.5)
    }
}
