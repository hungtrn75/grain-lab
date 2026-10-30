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
            CanvasView(viewModel: viewModel)
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
                    viewModel.showOriginal.toggle()
                }) {
                    Label(
                        viewModel.showOriginal ? "Showing Original" : "Before / After",
                        systemImage: viewModel.showOriginal ? "eye.slash.fill" : "eye.circle"
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
        guard viewModel.displayImage == nil && viewModel.loadedImageURL == nil else { return }
        
        // Create an appealing test photographic gradient CIImage
        if let demoImage = Self.createDemoTestImage() {
            viewModel.loadDirectImage(demoImage)
        }
    }
    
    private static func createDemoTestImage() -> CIImage? {
        let width: CGFloat = 1800
        let height: CGFloat = 1200
        
        // Generate a smooth photographic landscape gradient with warm sunset tones
        guard let gradFilter = CIFilter(name: "CILinearGradient") else { return nil }
        gradFilter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        gradFilter.setValue(CIVector(x: width, y: height), forKey: "inputPoint1")
        gradFilter.setValue(CIColor(red: 0.18, green: 0.22, blue: 0.35), forKey: "inputColor0") // Deep twilight navy
        gradFilter.setValue(CIColor(red: 0.88, green: 0.58, blue: 0.42), forKey: "inputColor1") // Warm golden hour
        
        guard let base = gradFilter.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return nil
        }
        
        // Add a gentle radial highlight (sun glow)
        if let radial = CIFilter(name: "CIRadialGradient") {
            radial.setValue(CIVector(x: width * 0.65, y: height * 0.55), forKey: "inputCenter")
            radial.setValue(100, forKey: "inputRadius0")
            radial.setValue(700, forKey: "inputRadius1")
            radial.setValue(CIColor(red: 1.0, green: 0.85, blue: 0.65, alpha: 0.7), forKey: "inputColor0")
            radial.setValue(CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0), forKey: "inputColor1")
            if let glow = radial.outputImage?.cropped(to: base.extent) {
                return glow.composited(over: base)
            }
        }
        
        return base
    }
}
