import Foundation
import Combine
import SwiftUI
import AppKit

public enum ExportFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG (.jpg)"
    case png = "PNG (.png)"
    case tiff = "TIFF (.tiff)"
    
    public var id: String { rawValue }
    
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        }
    }
}

@MainActor
public final class EditorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var currentPreset: FilmPreset = .defaultPreset
    @Published public var displayImage: NSImage?
    @Published public var originalImage: NSImage?
    @Published public var isProcessing: Bool = false
    @Published public var showOriginal: Bool = false
    
    // Zoom & Pan
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var panOffset: CGSize = .zero
    
    // Metadata & File Info
    @Published public var loadedImageURL: URL?
    @Published public var metadata: ImageMetadata?
    @Published public var errorMessage: String?
    @Published public var isExporting: Bool = false
    
    // Histogram data (256 normalized values)
    @Published public var histogramLuma: [Float] = Array(repeating: 0.0, count: 64)
    @Published public var histogramRed: [Float] = Array(repeating: 0.0, count: 64)
    @Published public var histogramGreen: [Float] = Array(repeating: 0.0, count: 64)
    @Published public var histogramBlue: [Float] = Array(repeating: 0.0, count: 64)
    
    // MARK: - Engine & Concurrency
    public let engine = CoreImageEngine()
    private var cancellables = Set<AnyCancellable>()
    private var renderTask: Task<Void, Never>?
    
    // MARK: - Initialization
    public init() {
        setupDebounce()
    }
    
    // MARK: - Debounce Pipeline
    private func setupDebounce() {
        // Setup Debounce: Only trigger rendering after user pauses slider movement (50ms)
        $currentPreset
            .dropFirst()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] newPreset in
                self?.processImage(with: newPreset)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Image Loading
    public func loadImage(from url: URL) {
        do {
            try engine.loadRAW(url: url)
            self.loadedImageURL = url
            self.metadata = engine.currentMetadata
            self.resetZoom()
            
            // Render baseline original image without adjustments for Before/After comparison
            if let originalCG = engine.render(with: .defaultPreset, targetMaxDimension: 2048) {
                let size = NSSize(width: originalCG.width, height: originalCG.height)
                self.originalImage = NSImage(cgImage: originalCG, size: size)
            }
            
            // Trigger first full render with active preset
            processImage(with: currentPreset, immediate: true)
        } catch {
            self.errorMessage = "Failed to load image: \(error.localizedDescription)"
            print("[EditorViewModel] Load error: \(error)")
        }
    }
    
    /// Loads a direct CIImage (e.g. for bundled demo images or unit tests)
    public func loadDirectImage(_ ciImage: CIImage) {
        engine.loadDirect(image: ciImage)
        self.loadedImageURL = nil
        self.metadata = engine.currentMetadata
        self.resetZoom()
        
        if let originalCG = engine.render(with: .defaultPreset, targetMaxDimension: 2048) {
            let size = NSSize(width: originalCG.width, height: originalCG.height)
            self.originalImage = NSImage(cgImage: originalCG, size: size)
        }
        
        processImage(with: currentPreset, immediate: true)
    }
    
    // MARK: - Background Processing
    public func processImage(with preset: FilmPreset, immediate: Bool = false) {
        // Cancel previous in-flight render task to prevent backlog
        renderTask?.cancel()
        self.isProcessing = true
        
        let engine = self.engine
        
        renderTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Execute heavy GPU pipeline on background thread
            let renderResult: (CGImage, [Float], [Float], [Float], [Float])? = await Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil }
                
                // Downscale to 2048px max dimension for fast 60fps responsive editing
                guard let cgImage = engine.render(with: preset, targetMaxDimension: 2048) else {
                    return nil
                }
                
                guard !Task.isCancelled else { return nil }
                let (luma, r, g, b) = Self.computeHistogram(for: cgImage, bins: 64)
                
                return (cgImage, luma, r, g, b)
            }.value
            
            guard !Task.isCancelled else { return }
            
            if let (cgImage, luma, r, g, b) = renderResult {
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                self.displayImage = NSImage(cgImage: cgImage, size: size)
                self.histogramLuma = luma
                self.histogramRed = r
                self.histogramGreen = g
                self.histogramBlue = b
            }
            self.isProcessing = false
        }
    }
    
    // MARK: - Preset Application
    public func applyPreset(_ preset: FilmPreset) {
        // Retain original preset ID or assign new ID
        self.currentPreset = preset
    }
    
    public func resetAdjustments() {
        self.currentPreset = .defaultPreset
    }
    
    // MARK: - Zoom & Pan Controls
    public func resetZoom() {
        self.zoomScale = 1.0
        self.panOffset = .zero
    }
    
    public func zoomIn() {
        self.zoomScale = min(self.zoomScale * 1.25, 8.0)
    }
    
    public func zoomOut() {
        self.zoomScale = max(self.zoomScale / 1.25, 0.2)
    }
    
    public func setActualSize() {
        self.zoomScale = 1.0
        self.panOffset = .zero
    }
    
    // MARK: - Image Export
    public func exportImage(to destinationURL: URL, format: ExportFormat, quality: CGFloat = 0.95) async throws {
        self.isExporting = true
        defer { self.isExporting = false }
        
        let engine = self.engine
        let preset = self.currentPreset
        
        // Render full resolution without downsampling
        guard let fullCGImage = engine.render(with: preset, targetMaxDimension: nil) else {
            throw EngineError.renderingFailed
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: fullCGImage)
        bitmapRep.size = NSSize(width: fullCGImage.width, height: fullCGImage.height)
        
        let fileData: Data?
        switch format {
        case .jpeg:
            fileData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case .png:
            fileData = bitmapRep.representation(using: .png, properties: [:])
        case .tiff:
            fileData = bitmapRep.representation(using: .tiff, properties: [:])
        }
        
        guard let data = fileData else {
            throw EngineError.renderingFailed
        }
        
        try data.write(to: destinationURL, options: .atomic)
    }
    
    // MARK: - Histogram Computation Helper
    nonisolated private static func computeHistogram(for cgImage: CGImage, bins: Int) -> ([Float], [Float], [Float], [Float]) {
        let width = min(cgImage.width, 256)
        let height = min(cgImage.height, 256)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ([], [], [], [])
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var lumaCounts = [Float](repeating: 0, count: bins)
        var rCounts = [Float](repeating: 0, count: bins)
        var gCounts = [Float](repeating: 0, count: bins)
        var bCounts = [Float](repeating: 0, count: bins)
        
        let binFactor = Float(bins - 1) / 255.0
        
        for i in stride(from: 0, to: rawData.count, by: bytesPerPixel) {
            let r = rawData[i]
            let g = rawData[i + 1]
            let b = rawData[i + 2]
            
            let rBin = Int(Float(r) * binFactor)
            let gBin = Int(Float(g) * binFactor)
            let bBin = Int(Float(b) * binFactor)
            
            let luma = Float(r) * 0.299 + Float(g) * 0.587 + Float(b) * 0.114
            let lumaBin = Int(luma * binFactor)
            
            rCounts[rBin] += 1.0
            gCounts[gBin] += 1.0
            bCounts[bBin] += 1.0
            lumaCounts[lumaBin] += 1.0
        }
        
        // Normalize histograms to max 1.0
        let maxLuma = lumaCounts.max() ?? 1.0
        let maxR = rCounts.max() ?? 1.0
        let maxG = gCounts.max() ?? 1.0
        let maxB = bCounts.max() ?? 1.0
        
        let normLuma = lumaCounts.map { maxLuma > 0 ? $0 / maxLuma : 0 }
        let normR = rCounts.map { maxR > 0 ? $0 / maxR : 0 }
        let normG = gCounts.map { maxG > 0 ? $0 / maxG : 0 }
        let normB = bCounts.map { maxB > 0 ? $0 / maxB : 0 }
        
        return (normLuma, normR, normG, normB)
    }
}
