import XCTest
import CoreImage
import AppKit
@testable import GrainLab

final class GrainLabTests: XCTestCase {
    
    func testGeometryRotationCropAndStraighten() throws {
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80)))
        var geometry = PhotoGeometry()
        geometry.quarterTurns = 1
        var image = try XCTUnwrap(engine.render(with: .defaultPreset, targetMaxDimension: nil, geometry: geometry))
        XCTAssertEqual(image.width, 80)
        XCTAssertEqual(image.height, 120)
        geometry.crop = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        image = try XCTUnwrap(engine.render(with: .defaultPreset, targetMaxDimension: nil, geometry: geometry))
        XCTAssertEqual(image.width, 40)
        XCTAssertEqual(image.height, 60)
        geometry.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        geometry.straighten = 15
        image = try XCTUnwrap(engine.render(with: .defaultPreset, targetMaxDimension: nil, geometry: geometry))
        let bitmap = NSBitmapImageRep(cgImage: image)
        for point in [(0, 0), (79, 0), (0, 119), (79, 119)] {
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: point.0, y: point.1)).alphaComponent, 0.99)
        }
        geometry.quarterTurns = -1
        XCTAssertEqual(geometry.apply(to: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80))).extent.size, CGSize(width: 80, height: 120))
    }

    @MainActor
    func testFilmstripPreservesEditsAndPasteExcludesGeometry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80)))
        let image = try XCTUnwrap(engine.render(with: .defaultPreset))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let first = directory.appendingPathComponent("a.png")
        let second = directory.appendingPathComponent("b.png")
        try png.write(to: first)
        try png.write(to: second)
        let vm = EditorViewModel()
        vm.importPhotos([first, second, first])
        XCTAssertEqual(vm.photoURLs.count, 2)
        vm.currentPreset.exposure = 1.25
        vm.geometry.quarterTurns = 1
        vm.geometry.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        vm.copyAdjustments()
        vm.loadImage(from: second)
        XCTAssertEqual(vm.currentPreset.exposure, 0)
        XCTAssertEqual(vm.geometry, PhotoGeometry())
        vm.pasteAdjustments()
        XCTAssertEqual(vm.currentPreset.exposure, 1.25)
        XCTAssertEqual(vm.geometry, PhotoGeometry())
        vm.currentPreset.exposure = -0.5
        vm.loadImage(from: first)
        XCTAssertEqual(vm.currentPreset.exposure, 1.25)
        XCTAssertEqual(vm.geometry.quarterTurns, 1)
        vm.loadImage(from: second)
        XCTAssertEqual(vm.currentPreset.exposure, -0.5)
        vm.pasteAdjustmentsToAll()
        vm.loadImage(from: first)
        XCTAssertEqual(vm.currentPreset.exposure, 1.25)
        XCTAssertEqual(vm.geometry.quarterTurns, 1)
        let output = directory.appendingPathComponent("export.png")
        try await vm.exportImage(to: output, format: .png)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(exported.pixelsWide, 40)
        XCTAssertEqual(exported.pixelsHigh, 60)
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    @MainActor
    func testActivationKeepsPreviewAndDoesNotRestartRendering() async throws {
        let vm = EditorViewModel()
        XCTAssertTrue(vm.beginInitialImageLoading())
        XCTAssertFalse(vm.beginInitialImageLoading())
        vm.loadDirectImage(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48)))
        for _ in 0..<100 {
            if !vm.isProcessing { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let preview = try XCTUnwrap(vm.displayImage)
        vm.zoomScale = 2
        vm.panOffset = CGSize(width: 10, height: 20)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        // Assigning unchanged edits must not schedule another render either.
        vm.currentPreset = vm.currentPreset
        vm.geometry = vm.geometry
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(vm.displayImage === preview)
        XCTAssertFalse(vm.isProcessing)
        XCTAssertEqual(vm.zoomScale, 2)
        XCTAssertEqual(vm.panOffset, CGSize(width: 10, height: 20))
    }

    func testCancelledRenderDoesNotStartGPUWork() async {
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48)))
        let task = Task.detached { () -> CGImage? in
            while !Task.isCancelled { await Task.yield() }
            return engine.render(with: .defaultPreset)
        }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    @MainActor
    func testComparisonMatchesGeometryAndReusesBeforeForColorEdits() async throws {
        let vm = EditorViewModel()
        vm.geometry.quarterTurns = 1
        vm.geometry.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        vm.loadDirectImage(CIImage(color: CIColor(red: 0.3, green: 0.4, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 120, height: 80)))
        func settle() async throws {
            try await Task.sleep(nanoseconds: 100_000_000)
            for _ in 0..<200 {
                if !vm.isProcessing { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("Comparison render timed out")
        }
        try await settle()
        let before = try XCTUnwrap(vm.comparisonImage)
        XCTAssertEqual(before.size, CGSize(width: 40, height: 60))
        XCTAssertEqual(vm.displayImage?.size, before.size)
        vm.currentPreset.exposure = 1
        try await settle()
        XCTAssertTrue(vm.comparisonImage === before)
        let after = try XCTUnwrap(vm.displayImage)
        vm.toggleComparison()
        vm.comparisonPosition = 0.25
        try await settle()
        XCTAssertTrue(vm.showComparison)
        XCTAssertTrue(vm.displayImage === after)
        XCTAssertTrue(vm.comparisonImage === before)
        vm.geometry.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        try await settle()
        XCTAssertEqual(vm.comparisonImage?.size, CGSize(width: 80, height: 120))
        XCTAssertEqual(vm.displayImage?.size, vm.comparisonImage?.size)
    }

    func testLUTIntensityUsesNumericLinearWeight() throws {
        let engine = CoreImageEngine()
        let floats = Array(repeating: Float(1), count: 2 * 2 * 2 * 4)
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let lut = LUTData(dimension: 2, data: data)
        let black = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1, height: 1))
        let context = CIContext()
        for amount: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
            let result = engine.applyLUT(to: black, data: lut, intensity: amount)
            var pixel = [Float](repeating: 0, count: 4)
            context.render(result, toBitmap: &pixel, rowBytes: 16, bounds: black.extent,
                           format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
            XCTAssertEqual(pixel[0], Float(amount), accuracy: 0.005)
        }
    }

    func testSRGBCubeSamplesEncodedRGBWithoutChannelSwap() throws {
        let dimension = 5
        var floats: [Float] = []
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    floats += [Float(b) / 4, Float(r) / 4, Float(g) / 4, 1]
                }
            }
        }
        let lut = LUTData(dimension: dimension, data: floats.withUnsafeBufferPointer { Data(buffer: $0) })
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let input: [Float] = [0.25, 0.5, 0.75, 1]
        let image = input.withUnsafeBytes {
            CIImage(bitmapData: Data($0), bytesPerRow: 16, size: CGSize(width: 1, height: 1), format: .RGBAf, colorSpace: srgb)
        }
        let result = CoreImageEngine().applyLUT(to: image, data: lut, intensity: 1)
        var pixel = [Float](repeating: 0, count: 4)
        CIContext().render(result, toBitmap: &pixel, rowBytes: 16, bounds: image.extent, format: .RGBAf, colorSpace: srgb)
        for (actual, expected) in zip(pixel, [Float(0.75), 0.25, 0.5, 1]) {
            XCTAssertEqual(actual, expected, accuracy: 0.005)
        }
    }

    @MainActor
    func testLUTOnlyClearsColorEditsAndPreservesGeometry() {
        let vm = EditorViewModel()
        vm.currentPreset = .kodakPortra400
        vm.geometry.quarterTurns = 1
        vm.geometry.straighten = 3
        let geometry = vm.geometry
        vm.applyLUTOnly("Velvia.cube")
        XCTAssertEqual(vm.geometry, geometry)
        XCTAssertEqual(vm.currentPreset.lutFileName, "Velvia.cube")
        XCTAssertEqual(vm.currentPreset.lutIntensity, 1)
        XCTAssertEqual(vm.currentPreset.temperature, 5500)
        XCTAssertEqual(vm.currentPreset.exposure, 0)
        XCTAssertEqual(vm.currentPreset.contrast, 1)
        XCTAssertEqual(vm.currentPreset.grainIntensity, 0)
        XCTAssertEqual(vm.currentPreset.toneCurvePoints, FilmPreset.defaultPreset.toneCurvePoints)
    }

    func testLightEffectsLegacyPresetAndRoundTrip() throws {
        let legacy = try JSONEncoder().encode(FilmPreset.kodakPortra400)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        object.removeValue(forKey: "lightEffects")
        var preset = try JSONDecoder().decode(FilmPreset.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(preset.halationAmount, 0)
        XCTAssertEqual(preset.bloomAmount, 0)
        preset.halationAmount = 0.4
        preset.bloomAmount = 0.3
        preset.halationRadius = 20
        preset.lightThreshold = 0.7
        let restored = try JSONDecoder().decode(FilmPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(restored, preset)
    }

    func testHalationCreatesWarmHaloAndBloomNeutralGlow() throws {
        let engine = CoreImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 512, height: 256)
        let dark = CIImage(color: .black).cropped(to: extent)
        let source = CIImage(color: .white).cropped(to: CGRect(x: 220, y: 80, width: 72, height: 96)).composited(over: dark)
        let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])
        func pixel(_ image: CIImage, x: Int, y: Int) -> [Float] {
            var values = [Float](repeating: 0, count: 4)
            context.render(image, toBitmap: &values, rowBytes: 16, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf,
                           colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)
            return values
        }
        XCTAssertTrue(engine.applyLightEffects(to: source, preset: .defaultPreset) === source)
        var preset = FilmPreset.defaultPreset
        preset.halationAmount = 1
        preset.halationRadius = 40
        let halation = engine.applyLightEffects(to: source, preset: preset)
        let halo = pixel(halation, x: 215, y: 128)
        XCTAssertGreaterThan(halo[0], 0.01)
        XCTAssertGreaterThan(halo[0], halo[1] * 3)
        XCTAssertGreaterThan(halo[1], halo[2])
        XCTAssertEqual(halation.extent, extent)
        let black = pixel(engine.applyLightEffects(to: dark, preset: preset), x: 100, y: 100)
        XCTAssertEqual(black[0], 0, accuracy: 0.001)
        preset.halationAmount = 0
        preset.bloomAmount = 1
        preset.bloomRadius = 80
        let glow = pixel(engine.applyLightEffects(to: source, preset: preset), x: 215, y: 128)
        XCTAssertGreaterThan(glow[0], 0.01)
        XCTAssertEqual(glow[0], glow[1], accuracy: 0.002)
        XCTAssertEqual(glow[1], glow[2], accuracy: 0.002)
        XCTAssertEqual(glow[3], 1, accuracy: 0.001)
        // Normalized radii should produce the same halo at proportional positions.
        let small = source.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        let smallGlow = pixel(engine.applyLightEffects(to: small, preset: preset), x: 107, y: 64)
        XCTAssertEqual(smallGlow[0], glow[0], accuracy: 0.04)
    }

    func testLUTThumbnailIncludesGeometryAndEffects() throws {
        let engine = CoreImageEngine()
        let extent = CGRect(x: 0, y: 0, width: 300, height: 200)
        let source = CIImage(color: .white).cropped(to: CGRect(x: 100, y: 70, width: 50, height: 60))
            .composited(over: CIImage(color: .black).cropped(to: extent))
        engine.loadDirect(image: source)
        var preset = FilmPreset.defaultPreset
        preset.bloomAmount = 0.5
        preset.halationAmount = 0.5
        var geometry = PhotoGeometry()
        geometry.quarterTurns = 1
        let base = try XCTUnwrap(engine.makeLUTPreviewSource(preset: preset, geometry: geometry))
        XCTAssertEqual(base.width, 200)
        XCTAssertEqual(base.height, 300)
        let thumbnail = try XCTUnwrap(engine.renderLUTThumbnail(source: base, preset: preset, lut: nil))
        let full = try XCTUnwrap(engine.render(with: preset, targetMaxDimension: 384, geometry: geometry))
        XCTAssertEqual(thumbnail.width, full.width)
        XCTAssertEqual(thumbnail.height, full.height)
        let previewPixel = try XCTUnwrap(NSBitmapImageRep(cgImage: thumbnail).colorAt(x: 90, y: 150))
        let fullPixel = try XCTUnwrap(NSBitmapImageRep(cgImage: full).colorAt(x: 90, y: 150))
        XCTAssertEqual(previewPixel.redComponent, fullPixel.redComponent, accuracy: 0.02)
    }

    @MainActor
    func testLUTBrowserShowsBypassAndReportsInvalidLUT() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = directory.appendingPathComponent("valid.cube")
        let bad = directory.appendingPathComponent("invalid.cube")
        let cube = "LUT_3D_SIZE 2\n" + Array(repeating: "1 0 0", count: 8).joined(separator: "\n")
        try cube.write(to: good, atomically: true, encoding: .utf8)
        try "broken".write(to: bad, atomically: true, encoding: .utf8)
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 60, height: 40)))
        let model = LUTBrowserModel()
        await model.load(engine: engine, preset: .defaultPreset, geometry: PhotoGeometry(), items: [
            LUTItem(name: "Valid", fileName: "valid.cube", url: good),
            LUTItem(name: "Invalid", fileName: "invalid.cube", url: bad)
        ])
        XCTAssertNotNil(model.thumbnails[LUTBrowserModel.bypassID])
        XCTAssertNotNil(model.thumbnails["valid.cube"])
        XCTAssertNotNil(model.failures["invalid.cube"])
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.completedIntensity, 1)
        let before = model.thumbnails["valid.cube"]
        var preset = FilmPreset.defaultPreset
        preset.lutIntensity = 0
        await model.load(engine: engine, preset: preset, geometry: PhotoGeometry(), items: [LUTItem(name: "Valid", fileName: "valid.cube", url: good)])
        XCTAssertEqual(model.completedIntensity, 0)
        XCTAssertFalse(model.thumbnails["valid.cube"] === before)
    }

    func testEyedropperCoordinatesRespectFitZoomAndPan() {
        let canvas = CGSize(width: 800, height: 600)
        let image = CGSize(width: 400, height: 200)
        XCTAssertNil(CanvasCoordinates.imagePoint(CGPoint(x: 400, y: 50), canvas: canvas, image: image, zoom: 1, pan: .zero))
        XCTAssertEqual(CanvasCoordinates.imagePoint(CGPoint(x: 400, y: 300), canvas: canvas, image: image, zoom: 1, pan: .zero), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(CanvasCoordinates.imagePoint(CGPoint(x: 50, y: 150), canvas: canvas, image: image, zoom: 2, pan: CGSize(width: 50, height: 50)), CGPoint(x: 0.25, y: 0.25))
    }

    func testEyedropperNeutralizesCastBeforeCreativeEdits() throws {
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60)))
        var preset = FilmPreset.defaultPreset
        let gains = try engine.measureWhiteBalance(at: CGPoint(x: 0.5, y: 0.5), preset: preset, geometry: PhotoGeometry())
        XCTAssertLessThan(gains.red, 1)
        XCTAssertGreaterThan(gains.blue, 1)
        preset.whiteBalanceGains = gains
        let corrected = try XCTUnwrap(engine.render(with: preset))
        let pixel = try XCTUnwrap(NSBitmapImageRep(cgImage: corrected).colorAt(x: 40, y: 30))
        XCTAssertEqual(pixel.redComponent, pixel.greenComponent, accuracy: 0.01)
        XCTAssertEqual(pixel.greenComponent, pixel.blueComponent, accuracy: 0.01)
        // Repeated sampling replaces rather than compounds the correction.
        XCTAssertEqual(try engine.measureWhiteBalance(at: CGPoint(x: 0.5, y: 0.5), preset: preset, geometry: PhotoGeometry()), gains)
        preset.exposure = 3
        preset.contrast = 1.8
        preset.grainIntensity = 1
        preset.lutFileName = "Ilford_HP5_Plus.cube"
        preset.bloomAmount = 1
        XCTAssertEqual(try engine.measureWhiteBalance(at: CGPoint(x: 0.5, y: 0.5), preset: preset, geometry: PhotoGeometry()), gains)
        let restored = try JSONDecoder().decode(FilmPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(restored.whiteBalanceGains, gains)
    }

    func testEyedropperRejectsUnreliableSamples() {
        XCTAssertThrowsError(try CoreImageEngine.neutralGains(red: 0, green: 0, blue: 0))
        XCTAssertThrowsError(try CoreImageEngine.neutralGains(red: 1, green: 1, blue: 1))
        XCTAssertThrowsError(try CoreImageEngine.neutralGains(red: 0.01, green: 0.9, blue: 0.01))
        XCTAssertThrowsError(try CoreImageEngine.neutralGains(red: 0.3, green: 0.3, blue: 0.3, alpha: 0))
    }

    @MainActor
    func testEyedropperAppliesAndCopiesSampledWB() async throws {
        let vm = EditorViewModel()
        vm.loadDirectImage(CIImage(color: CIColor(red: 0.6, green: 0.4, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 80, height: 60)))
        vm.toggleWhiteBalancePicker()
        vm.sampleWhiteBalance(at: CGPoint(x: 0.5, y: 0.5))
        for _ in 0..<200 {
            if !vm.isSamplingWhiteBalance { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(vm.currentPreset.whiteBalanceGains)
        XCTAssertFalse(vm.isPickingWhiteBalance)
        vm.copyAdjustments()
        vm.resetAdjustments()
        XCTAssertNil(vm.currentPreset.whiteBalanceGains)
        vm.pasteAdjustments()
        XCTAssertNotNil(vm.currentPreset.whiteBalanceGains)
        try await Task.sleep(nanoseconds: 200_000_000)
    }

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
    
    func testLUTRejectsUnsafeDimensionsAndUnsupportedData() {
        let parser = LUTParser()
        for size in ["-1", "0", "1", "129", "9223372036854775807"] {
            XCTAssertThrowsError(try parser.parse(string: "LUT_3D_SIZE \(size)"))
        }
        for row in ["nan 0 0", "inf 0 0", "bad data row", "0 0 0 1"] {
            XCTAssertThrowsError(try parser.parse(string: "LUT_3D_SIZE 2\n" + row))
        }
        XCTAssertThrowsError(try parser.parse(string: "LUT_3D_SIZE 2\nDOMAIN_MAX 2 2 2"))
        XCTAssertThrowsError(try parser.parse(string: "LUT_1D_SIZE 2"))
    }

    func testLUTAcceptsTabsAndInlineComments() throws {
        let rows = Array(repeating: "0\t0\t0 # sample", count: 8).joined(separator: "\n")
        let lut = try LUTParser().parse(string: "LUT_3D_SIZE\t2 # dimension\n" + rows)
        XCTAssertEqual(lut.data.count, 128)
    }

    func testLUTCacheInvalidationAfterReplacement() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".cube")
        defer { try? FileManager.default.removeItem(at: url) }
        let parser = LUTParser()
        func cube(_ value: String) -> String {
            "LUT_3D_SIZE 2\n" + Array(repeating: "\(value) 0 0", count: 8).joined(separator: "\n")
        }
        try cube("0").write(to: url, atomically: true, encoding: .utf8)
        let before = try parser.parse(from: url)
        try cube("1").write(to: url, atomically: true, encoding: .utf8)
        parser.invalidate(url: url)
        XCTAssertNotEqual(try parser.parse(from: url).data, before.data)
    }

    func testCurveWithShiftedXCoordinatesIsApplied() throws {
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8)))
        let neutral = try XCTUnwrap(engine.render(with: .defaultPreset))
        var preset = FilmPreset.defaultPreset
        preset.toneCurvePoints[1].x = 0.1
        preset.toneCurvePoints[2].x = 0.3
        let adjusted = try XCTUnwrap(engine.render(with: preset))
        XCTAssertNotEqual(neutral.dataProvider?.data as Data?, adjusted.dataProvider?.data as Data?)
    }

    func testFailedImportPreservesLoadedImage() throws {
        let engine = CoreImageEngine()
        engine.loadDirect(image: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 24)))
        XCTAssertThrowsError(try engine.loadRAW(url: URL(fileURLWithPath: "/nonexistent/grainlab.png")))
        let rendered = try XCTUnwrap(engine.render(with: .defaultPreset))
        XCTAssertEqual(rendered.width, 32)
        XCTAssertEqual(rendered.height, 24)
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
