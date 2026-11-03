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
                        imageLayer(image, size: geo.size)
                            .gesture(panGesture)
                            .gesture(zoomGesture)
                        if viewModel.isPickingWhiteBalance {
                            Color.clear.contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { value in
                                    guard !viewModel.isProcessing,
                                          let point = CanvasCoordinates.imagePoint(value.location, canvas: geo.size, image: image.size,
                                              zoom: viewModel.zoomScale, pan: viewModel.panOffset) else { return }
                                    viewModel.sampleWhiteBalance(at: point)
                                })
                                .onHover { inside in
                                    if inside { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
                                }
                                .onDisappear { NSCursor.arrow.set() }
                        }
                        if viewModel.showComparison, let before = viewModel.comparisonImage {
                            imageLayer(before, size: geo.size)
                                .mask(alignment: .leading) {
                                    Rectangle().frame(width: geo.size.width * viewModel.comparisonPosition)
                                }
                                .allowsHitTesting(false)
                            comparisonDivider(size: geo.size)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            viewModel.resetZoom()
                        } label: {
                            Label("Fit to Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    }
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
            
            if viewModel.isPickingWhiteBalance {
                VStack {
                    Spacer()
                    HStack {
                        Text("Click a neutral gray / white area")
                        Button("Cancel") { viewModel.toggleWhiteBalancePicker() }
                            .keyboardShortcut(.cancelAction)
                    }
                    .font(.caption).padding(10).background(.regularMaterial).cornerRadius(8)
                    .padding(.bottom, 64)
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
        .background {
            GeometryReader { geometry in
                OptionScrollZoomView { delta in
                    guard activeImage != nil else { return }
                    viewModel.zoomScale = min(max(viewModel.zoomScale * exp(delta * 0.01), 0.2), 8.0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func imageLayer(_ image: NSImage, size: CGSize) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size.width, height: size.height)
            .scaleEffect(viewModel.zoomScale * gestureZoom)
            .offset(x: viewModel.panOffset.width + gesturePan.width,
                    y: viewModel.panOffset.height + gesturePan.height)
    }

    private func comparisonDivider(size: CGSize) -> some View {
        ZStack {
            HStack {
                Text("BEFORE")
                Spacer()
                Text("AFTER")
            }
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .shadow(color: .black, radius: 3)
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            ZStack {
                Rectangle().fill(.white).frame(width: 2)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white))
                    .shadow(radius: 3)
            }
            .frame(width: 44, height: size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("comparisonCanvas"))
                .onChanged { value in
                    viewModel.comparisonPosition = min(max(value.location.x / max(size.width, 1), 0), 1)
                })
            .onTapGesture(count: 2) { viewModel.comparisonPosition = 0.5 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Before / After divider")
            .accessibilityValue("\(Int(viewModel.comparisonPosition * 100)) percent before")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: viewModel.comparisonPosition = min(viewModel.comparisonPosition + 0.05, 1)
                case .decrement: viewModel.comparisonPosition = max(viewModel.comparisonPosition - 0.05, 0)
                @unknown default: break
                }
            }
            .position(x: size.width * viewModel.comparisonPosition, y: size.height / 2)
        }
        .coordinateSpace(name: "comparisonCanvas")
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
                viewModel.toggleComparison()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.lefthalf.filled")
                    Text(viewModel.showComparison ? "Close Compare" : "Before / After")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.showComparison ? .orange : .secondary)
            .help("Drag the divider to compare before and after")
            
            Divider()
                .frame(height: 14)
            
            // Zoom Out
            Button(action: { viewModel.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom Out (⌘−)")
            
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
            .keyboardShortcut("=", modifiers: .command)
            .help("Zoom In (⌘= or ⌘+)")
            .background {
                // Also accept the shifted plus key on keyboards where + shares =.
                Button("Zoom In") { viewModel.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
            }
            
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
        guard !providers.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [Int: URL] = [:]
        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                if let url {
                    lock.lock()
                    urls[index] = url
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            viewModel.importPhotos(urls.sorted { $0.key < $1.key }.map(\.value))
        }
        return true
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage]
        if panel.runModal() == .OK {
            viewModel.importPhotos(panel.urls)
        }
    }
}

/// Observes scrolling inside the canvas without intercepting pan or pinch gestures.
private struct OptionScrollZoomView: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollObserverView {
        let view = ScrollObserverView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollObserverView, context: Context) {
        nsView.onScroll = onScroll
        nsView.startObservingIfNeeded()
    }

    static func dismantleNSView(_ nsView: ScrollObserverView, coordinator: ()) {
        nsView.stopObserving()
    }

    final class ScrollObserverView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            startObservingIfNeeded()
        }

        func startObservingIfNeeded() {
            guard window != nil, monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window,
                      (event.window == nil || event.window === window),
                      NSApp.keyWindow === window,
                      event.modifierFlags.contains(.option),
                      !self.isHiddenOrHasHiddenAncestor,
                      self.bounds.contains(self.convert(window.mouseLocationOutsideOfEventStream, from: nil)) else {
                    return event
                }
                // Trackpads report pixel deltas; wheel mice report much smaller steps.
                let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
                self.onScroll?(delta)
                return nil
            }
        }

        func stopObserving() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stopObserving() }
    }
}
