import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var viewModel = EditorViewModel()
    
    // Column visibility state
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - Left Column (Sidebar: Files & Presets)
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } content: {
            // MARK: - Middle Column (Center Canvas: Zoom, Pan, Image Viewport)
            VStack(spacing: 0) {
                CanvasView(viewModel: viewModel)
                if !viewModel.photoURLs.isEmpty {
                    Divider()
                    FilmstripView(viewModel: viewModel)
                }
            }
                .navigationSplitViewColumnWidth(min: 400, ideal: 700)
        } detail: {
            // MARK: - Right Column (Inspector: Controls, Sliders, Curves, LUT, Grain)
            InspectorView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .navigationTitle(navigationTitleText)
        .navigationSubtitle(navigationSubtitleText)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Before / After Comparison
                Button(action: {
                    viewModel.toggleComparison()
                }) {
                    Label(
                        viewModel.showComparison ? "Close Compare" : "Before / After",
                        systemImage: "rectangle.lefthalf.filled"
                    )
                }
                .help("Toggle Before / After (Original vs Simulated)")
                .disabled(viewModel.displayImage == nil)
                
                // Reset Zoom
                Button(action: {
                    viewModel.resetZoom()
                }) {
                    Label("Fit View", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit image to canvas")
                .disabled(viewModel.displayImage == nil)
            }
        }
        .alert("GrainLab Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .onAppear {
            loadInitialDemoIfEmpty()
        }
    }
    
    private var navigationTitleText: String {
        if let url = viewModel.loadedImageURL {
            return url.lastPathComponent
        }
        return "GrainLab • RAW Film Studio"
    }
    
    private var navigationSubtitleText: String {
        return "Active Preset: \(viewModel.currentPreset.name)"
    }
    
    /// Preloads a clean photographic demo gradient/pattern CIImage so the user sees live film simulation right away
    private func loadInitialDemoIfEmpty() {
        guard viewModel.beginInitialImageLoading() else { return }
        
        // Create an appealing test photographic gradient CIImage
        if let demoImage = Self.createDemoTestImage() {
            viewModel.loadDirectImage(demoImage)
        }
    }
    
    private static func createDemoTestImage() -> CIImage? {
        let width: CGFloat = 1800
        let height: CGFloat = 1200
        
        // Generate a natural photographic landscape with rich sky blue, natural greens, and neutral tones
        // Sky to horizon gradient
        guard let skyFilter = CIFilter(name: "CILinearGradient") else { return nil }
        skyFilter.setValue(CIVector(x: width * 0.5, y: height), forKey: "inputPoint0")
        skyFilter.setValue(CIVector(x: width * 0.5, y: height * 0.4), forKey: "inputPoint1")
        skyFilter.setValue(CIColor(red: 0.35, green: 0.62, blue: 0.88), forKey: "inputColor0") // Deep natural blue sky
        skyFilter.setValue(CIColor(red: 0.85, green: 0.89, blue: 0.92), forKey: "inputColor1") // Soft horizon
        
        guard let sky = skyFilter.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return nil
        }
        
        // Rolling green hills / landscape at bottom
        guard let groundFilter = CIFilter(name: "CILinearGradient") else { return sky }
        groundFilter.setValue(CIVector(x: width * 0.5, y: height * 0.42), forKey: "inputPoint0")
        groundFilter.setValue(CIVector(x: width * 0.5, y: 0), forKey: "inputPoint1")
        groundFilter.setValue(CIColor(red: 0.28, green: 0.52, blue: 0.25, alpha: 0.95), forKey: "inputColor0") // Sunlit green meadow
        groundFilter.setValue(CIColor(red: 0.14, green: 0.32, blue: 0.18, alpha: 1.0), forKey: "inputColor1")  // Deep forest green
        
        let ground = groundFilter.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: width, height: height * 0.42))
        
        var combined = sky
        if let g = ground {
            combined = g.composited(over: sky)
        }
        
        // Subtle soft cloud highlight
        if let cloud = CIFilter(name: "CIRadialGradient") {
            cloud.setValue(CIVector(x: width * 0.40, y: height * 0.65), forKey: "inputCenter")
            cloud.setValue(50, forKey: "inputRadius0")
            cloud.setValue(450, forKey: "inputRadius1")
            cloud.setValue(CIColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 0.45), forKey: "inputColor0")
            cloud.setValue(CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0), forKey: "inputColor1")
            if let cloudGlow = cloud.outputImage?.cropped(to: combined.extent) {
                combined = cloudGlow.composited(over: combined)
            }
        }
        
        return combined
    }
}
