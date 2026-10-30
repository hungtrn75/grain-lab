import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct CanvasView: View {
    @ObservedObject var viewModel: EditorViewModel
    
    // Interactive gestures temporary state
    @GestureState private var gestureZoom: CGFloat = 1.0
    @GestureState private var gesturePan: CGSize = .zero
    
    @State private var isTargetedForDrop = false
    
    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            // Dark viewport background (standard in photo editing apps like Lightroom/Capture One)
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            
            if let image = activeImage {
                GeometryReader { geo in
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(viewModel.zoomScale * gestureZoom)
                            .offset(
                                x: viewModel.panOffset.width + gesturePan.width,
                                y: viewModel.panOffset.height + gesturePan.height
                            )
                            .gesture(panGesture)
                            .gesture(zoomGesture)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .clipped()
                }
            } else {
                emptyDropZone
            }
            
            // Top overlay: "BEFORE" badge when in comparison mode
            if viewModel.showOriginal {
                VStack {
                    HStack {
                        Text("ORIGINAL (BEFORE)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(6)
                            .padding(16)
                        Spacer()
                    }
                    Spacer()
                }
            }
            
            // Processing spinner in top right
            if viewModel.isProcessing {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("GPU Processing...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(6)
                        .padding(16)
                    }
                    Spacer()
                }
            }
            
            // Bottom Canvas Toolbar (Zoom, 1:1, Fit, Before/After)
            if activeImage != nil {
                VStack {
                    Spacer()
                    canvasBottomToolbar
                        .padding(.bottom, 16)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - Active Display Image
    private var activeImage: NSImage? {
        if viewModel.showOriginal {
            return viewModel.originalImage ?? viewModel.displayImage
        }
        return viewModel.displayImage
    }
    
    // MARK: - Empty State
    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                Text("No Image Loaded")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Drag & drop a RAW photo here (.NEF, .CR2, .ARW, .DNG) or click Import")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Open RAW File...") {
                openFile()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                )
                .padding(20)
        )
    }
    
    // MARK: - Bottom Floating Toolbar
    private var canvasBottomToolbar: some View {
        HStack(spacing: 12) {
            // Before / After Comparison Button
            Button(action: {
                viewModel.showOriginal.toggle()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.showOriginal ? "eye.fill" : "eye")
                    Text(viewModel.showOriginal ? "Showing Original" : "Before / After")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.showOriginal ? .orange : .secondary)
            .help("Toggle unedited original RAW image comparison")
            
            Divider()
                .frame(height: 14)
            
            // Zoom Out
            Button(action: { viewModel.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            
            // Zoom Label
            Text("\(Int(round(viewModel.zoomScale * 100)))%")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 42)
            
            // Zoom In
            Button(action: { viewModel.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 14)
            
            // Fit to View
            Button("Fit") {
                viewModel.resetZoom()
            }
            .font(.caption2)
            .buttonStyle(.borderless)
            
            // 1:1 Pixel Actual Size
            Button("1:1") {
                viewModel.setActualSize()
            }
            .font(.caption2)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
    
    // MARK: - Gestures
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureZoom) { value, state, _ in
                state = value
            }
            .onEnded { value in
                viewModel.zoomScale = min(max(viewModel.zoomScale * value, 0.2), 8.0)
            }
    }
    
    private var panGesture: some Gesture {
        DragGesture()
            .updating($gesturePan) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                viewModel.panOffset.width += value.translation.width
                viewModel.panOffset.height += value.translation.height
            }
    }
    
    // MARK: - Drag & Drop Handling
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            
            DispatchQueue.main.async {
                self.viewModel.loadImage(from: url)
            }
        }
        return true
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadImage(from: url)
        }
    }
}
