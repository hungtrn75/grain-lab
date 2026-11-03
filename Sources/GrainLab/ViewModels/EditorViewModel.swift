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
    @Published public var geometry = PhotoGeometry()
    @Published public private(set) var photoURLs: [URL] = []
    @Published public private(set) var copiedAdjustments: FilmPreset?
    private var didInitializeImage = false

    /// View appearance can repeat during window/layout changes; initialize only once.
    public func beginInitialImageLoading() -> Bool {
        guard !didInitializeImage, loadedImageURL == nil, originalImage == nil else { return false }
        didInitializeImage = true
        return true
    }

    private var photoEdits: [URL: (FilmPreset, PhotoGeometry, [AdjustmentLayer])] = [:]

    public func importPhotos(_ urls: [URL]) {
        let unique = urls.map { $0.standardizedFileURL }.filter { $0.isFileURL }
        for url in unique where !photoURLs.contains(url) { photoURLs.append(url) }
        if let first = unique.first { loadImage(from: first) }
    }

    public func copyAdjustments() { copiedAdjustments = currentPreset }
    public func pasteAdjustments() {
        guard let copiedAdjustments else { return }
        currentPreset = copiedAdjustments
    }

    public func pasteAdjustmentsToAll() {
        guard let copiedAdjustments else { return }
        for url in photoURLs {
            photoEdits[url] = (copiedAdjustments, url == loadedImageURL ? geometry : (photoEdits[url]?.1 ?? PhotoGeometry()), url == loadedImageURL ? layers : (photoEdits[url]?.2 ?? []))
        }
        currentPreset = copiedAdjustments
    }

    @Published public var layers: [AdjustmentLayer] = []
    @Published public var selectedLayerID: UUID? { didSet { refreshMaskPreview() } }
    @Published public var isEditingMask = false {
        didSet {
            if isEditingMask { cancelWhiteBalanceSampling(); showComparison = false; showOriginal = false }
            refreshMaskPreview()
        }
    }
    @Published public var showMaskOverlay = true { didSet { refreshMaskPreview() } }
    @Published public private(set) var maskOverlay: NSImage?
    @Published public private(set) var sourceImageSize: CGSize = .zero
    @Published public var brushRadius: CGFloat = 0.04
    @Published public var brushHardness: CGFloat = 0.5
    @Published public var brushFlow: CGFloat = 1
    @Published public var brushErase = false
    private var maskTask: Task<Void, Never>?
    private var maskGeneration = UUID()

    public var selectedLayer: AdjustmentLayer? { layers.first { $0.id == selectedLayerID } }

    public func addLayer(_ kind: LayerMaskKind) {
        let layer = AdjustmentLayer(kind: kind, name: "\(kind.rawValue) \(layers.count + 1)")
        layers.append(layer)
        selectedLayerID = layer.id
        isEditingMask = true
    }

    public func updateSelectedLayer(_ change: (inout AdjustmentLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }) else { return }
        change(&layers[index])
    }

    public func deleteSelectedLayer() {
        layers.removeAll { $0.id == selectedLayerID }
        selectedLayerID = layers.last?.id
        if layers.isEmpty { isEditingMask = false }
    }

    public func moveSelectedLayer(_ offset: Int) {
        guard let index = layers.firstIndex(where: { $0.id == selectedLayerID }), layers.indices.contains(index + offset) else { return }
        layers.swapAt(index, index + offset)
    }

    public func refreshMaskPreview() {
        maskTask?.cancel()
        let generation = UUID()
        maskGeneration = generation
        guard isEditingMask, showMaskOverlay, let layer = selectedLayer else { maskOverlay = nil; return }
        let engine = engine, geometry = geometry
        maskTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { engine.renderMaskOverlay(layer: layer, geometry: geometry) }
            let image = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard let self, !Task.isCancelled, self.maskGeneration == generation else { return }
            if let image { self.maskOverlay = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
        }
    }

    @Published public var isPickingWhiteBalance = false
    @Published public private(set) var isSamplingWhiteBalance = false
    @Published public private(set) var whiteBalanceMessage: String?
    private var whiteBalanceTask: Task<Void, Never>?
    private var whiteBalanceGeneration = UUID()

    public func toggleWhiteBalancePicker() {
        isEditingMask = false
        if isPickingWhiteBalance {
            cancelWhiteBalanceSampling()
            return
        }
        isPickingWhiteBalance = true
        whiteBalanceMessage = nil
        if isPickingWhiteBalance {
            showComparison = false
            showOriginal = false
        }
    }

    private func cancelWhiteBalanceSampling() {
        whiteBalanceGeneration = UUID()
        whiteBalanceTask?.cancel()
        isPickingWhiteBalance = false
        isSamplingWhiteBalance = false
        whiteBalanceMessage = nil
    }

    public func sampleWhiteBalance(at point: CGPoint) {
        guard !isSamplingWhiteBalance else { return }
        let generation = UUID()
        whiteBalanceGeneration = generation
        let preset = currentPreset
        let geometry = geometry
        let url = loadedImageURL
        let engine = engine
        isSamplingWhiteBalance = true
        whiteBalanceMessage = nil
        whiteBalanceTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                try engine.measureWhiteBalance(at: point, preset: preset, geometry: geometry)
            }
            do {
                let gains = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard let self, !Task.isCancelled, self.whiteBalanceGeneration == generation else { return }
                self.isSamplingWhiteBalance = false
                guard self.loadedImageURL == url, self.geometry == geometry, self.currentPreset == preset else {
                    self.whiteBalanceMessage = "Image or edits changed. Please pick a neutral area again."
                    return
                }
                self.currentPreset.whiteBalanceGains = gains
                self.isPickingWhiteBalance = false
                self.whiteBalanceMessage = "Neutral white balance applied."
            } catch {
                guard let self, !Task.isCancelled, self.whiteBalanceGeneration == generation else { return }
                self.isSamplingWhiteBalance = false
                self.whiteBalanceMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Published Properties
    @Published public var currentPreset: FilmPreset = .defaultPreset
    @Published public var displayImage: NSImage?
    @Published public var originalImage: NSImage?
    @Published public var isProcessing: Bool = false
    @Published public var showOriginal: Bool = false
    @Published public var showComparison: Bool = false
    @Published public var comparisonPosition: CGFloat = 0.5
    @Published public private(set) var comparisonImage: NSImage?
    private var comparisonGeometry: PhotoGeometry?

    public func toggleComparison() {
        isEditingMask = false
        showOriginal = false
        showComparison.toggle()
    }
    
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
    private var renderWorker: Task<(CGImage, CGImage?, [Float], [Float], [Float], [Float])?, Never>?
    
    // MARK: - Initialization
    public init() {
        setupDebounce()
    }
    
    // MARK: - Debounce Pipeline
    private func setupDebounce() {
        // Setup Debounce: Only trigger rendering after user pauses slider movement (50ms)
        $currentPreset.combineLatest($geometry, $layers)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 }
            .dropFirst()
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] newPreset, _, _ in
                self?.processImage(with: newPreset)
                self?.refreshMaskPreview()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Image Loading
    public func loadImage(from url: URL) {
        let url = url.standardizedFileURL
        guard url != loadedImageURL else { return }
        cancelWhiteBalanceSampling()
        if let previous = loadedImageURL { photoEdits[previous] = (currentPreset, geometry, layers) }
        do {
            try engine.loadRAW(url: url)
            renderTask?.cancel()
            renderWorker?.cancel()
            if !photoURLs.contains(url) { photoURLs.append(url) }
            let edits = photoEdits[url]
            currentPreset = edits?.0 ?? .defaultPreset
            geometry = edits?.1 ?? PhotoGeometry()
            layers = edits?.2 ?? []
            selectedLayerID = layers.last?.id
            isEditingMask = false
            sourceImageSize = engine.sourceImageSize ?? .zero
            errorMessage = nil
            displayImage = nil
            originalImage = nil
            comparisonImage = nil
            comparisonGeometry = nil
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
        cancelWhiteBalanceSampling()
        engine.loadDirect(image: ciImage)
        sourceImageSize = ciImage.extent.size
        layers = []
        selectedLayerID = nil
        isEditingMask = false
        comparisonImage = nil
        comparisonGeometry = nil
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
        renderWorker?.cancel()
        self.isProcessing = true
        
        let engine = self.engine
        let geometry = self.geometry
        let layers = self.layers
        let needsComparison = comparisonImage == nil || comparisonGeometry != geometry
        
        renderTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            
            // Execute heavy GPU pipeline on background thread
            let worker = Task.detached(priority: .userInitiated) { () -> (CGImage, CGImage?, [Float], [Float], [Float], [Float])? in
                guard !Task.isCancelled else { return nil }
                
                // Downscale to 2048px max dimension for fast 60fps responsive editing
                guard let cgImage = engine.render(with: preset, targetMaxDimension: 2048, geometry: geometry, layers: layers) else {
                    return nil
                }
                
                guard !Task.isCancelled else { return nil }
                let (luma, r, g, b) = Self.computeHistogram(for: cgImage, bins: 64)
                
                // Cache the neutral image for this geometry; color edits and divider
                // movement reuse it without another RAW decode or GPU render.
                var before: CGImage?
                if needsComparison {
                    guard !Task.isCancelled,
                          let neutral = engine.render(with: .defaultPreset, targetMaxDimension: 2048, geometry: geometry) else { return nil }
                    before = neutral
                }
                return (cgImage, before, luma, r, g, b)
            }
            self.renderWorker = worker
            let renderResult = await worker.value
            
            guard !Task.isCancelled else { return }
            
            if let (cgImage, before, luma, r, g, b) = renderResult {
                if let before {
                    self.comparisonImage = NSImage(cgImage: before, size: NSSize(width: before.width, height: before.height))
                    self.comparisonGeometry = geometry
                }
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
    
    /// Clear color adjustments while retaining this photo's crop and rotation.
    public func applyLUTOnly(_ fileName: String) {
        var preset = FilmPreset.defaultPreset
        preset.id = UUID()
        preset.name = (fileName as NSString).deletingPathExtension
        preset.lutFileName = fileName
        preset.lutIntensity = 1
        currentPreset = preset
    }

    public func resetAdjustments() {
        layers = []
        selectedLayerID = nil
        isEditingMask = false
        self.currentPreset = .defaultPreset
        self.geometry = PhotoGeometry()
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
        let geometry = self.geometry
        let layers = self.layers
        
        try await Task.detached(priority: .userInitiated) {
            // Render full resolution without downsampling
            guard let fullCGImage = engine.render(with: preset, targetMaxDimension: nil, geometry: geometry, layers: layers) else {
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
        
            try Task.checkCancellation()
            try data.write(to: destinationURL, options: .atomic)
        }.value
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
