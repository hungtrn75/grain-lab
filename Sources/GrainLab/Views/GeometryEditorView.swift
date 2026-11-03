import SwiftUI

struct GeometryEditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    @State private var showingCrop = false
    private var crop: CGRect { viewModel.geometry.crop }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CROP & ROTATE").font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)
                Spacer()
                Button("Reset") { viewModel.geometry = PhotoGeometry() }.font(.caption2)
            }
            HStack {
                Button { viewModel.geometry.quarterTurns -= 1 } label: { Label("Left", systemImage: "rotate.left") }
                Button { viewModel.geometry.quarterTurns += 1 } label: { Label("Right", systemImage: "rotate.right") }
            }
            Button("Select Crop on Image…") { showingCrop = true }
            Text(String(format: "Straighten: %+.1f°", viewModel.geometry.straighten)).font(.caption)
            Slider(value: $viewModel.geometry.straighten, in: -15...15, step: 0.1)
            HStack {
                Text("Crop").font(.caption)
                Spacer()
                Menu("Aspect Ratio") {
                    Button("Original / Full Frame") { viewModel.geometry.crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
                    Button("1:1") { setAspect(1) }
                    Button("4:3") { setAspect(4.0 / 3) }
                    Button("3:2") { setAspect(1.5) }
                    Button("16:9") { setAspect(16.0 / 9) }
                    Button("9:16") { setAspect(9.0 / 16) }
                }
            }
            cropSlider("Width", value: crop.width, range: 0.1...1) { value in
                viewModel.geometry.crop.size.width = value
                viewModel.geometry.crop.origin.x = min(crop.minX, 1 - value)
            }
            cropSlider("Height", value: crop.height, range: 0.1...1) { value in
                viewModel.geometry.crop.size.height = value
                viewModel.geometry.crop.origin.y = min(crop.minY, 1 - value)
            }
            cropSlider("Horizontal position", value: crop.minX / max(1 - crop.width, 0.0001), range: 0...1) {
                viewModel.geometry.crop.origin.x = $0 * (1 - crop.width)
            }
            cropSlider("Vertical position", value: crop.minY / max(1 - crop.height, 0.0001), range: 0...1) {
                viewModel.geometry.crop.origin.y = $0 * (1 - crop.height)
            }
            Text("Crop updates live and applies to export. Width and height sliders allow a free crop.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .disabled(viewModel.displayImage == nil)
        .sheet(isPresented: $showingCrop) { CropSelectionSheet(viewModel: viewModel) }
    }

    private func cropSlider(_ title: String, value: CGFloat, range: ClosedRange<CGFloat>, set: @escaping (CGFloat) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(Int(value * 100))%").font(.caption)
            Slider(value: Binding(get: { value }, set: set), in: range)
        }
    }

    private func setAspect(_ ratio: CGFloat) {
        guard let meta = viewModel.metadata, meta.width > 0, meta.height > 0 else { return }
        let rotated = viewModel.geometry.quarterTurns % 2 != 0
        let aspect = rotated ? CGFloat(meta.height) / CGFloat(meta.width) : CGFloat(meta.width) / CGFloat(meta.height)
        let width = min(1, ratio / aspect)
        let height = min(1, aspect / ratio)
        viewModel.geometry.crop = CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }
}

private struct CropSelectionSheet: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    @State private var selection = CGRect(x: 0, y: 0, width: 1, height: 1)

    var body: some View {
        VStack(spacing: 12) {
            Text("Drag on the image to select a crop").font(.headline)
            GeometryReader { geo in
                if let image {
                    let scale = min(geo.size.width / image.size.width, geo.size.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
                        Rectangle().fill(.black.opacity(0.4))
                            .mask {
                                Rectangle().overlay {
                                    Rectangle().frame(width: selection.width * size.width, height: selection.height * size.height)
                                        .position(x: selection.midX * size.width, y: selection.midY * size.height)
                                        .blendMode(.destinationOut)
                                }.compositingGroup()
                            }
                        Rectangle().stroke(.white, lineWidth: 2)
                            .frame(width: selection.width * size.width, height: selection.height * size.height)
                            .position(x: selection.midX * size.width, y: selection.midY * size.height)
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        let start = CGPoint(x: min(max(value.startLocation.x / size.width, 0), 1), y: min(max(value.startLocation.y / size.height, 0), 1))
                        let end = CGPoint(x: min(max(value.location.x / size.width, 0), 1), y: min(max(value.location.y / size.height, 0), 1))
                        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Full Frame") { selection = CGRect(x: 0, y: 0, width: 1, height: 1) }
                Spacer()
                Button("Apply Crop") {
                    viewModel.geometry.crop = CGRect(x: selection.minX, y: 1 - selection.maxY, width: selection.width, height: selection.height)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(image == nil || selection.width < 0.01 || selection.height < 0.01)
            }
        }
        .padding(20).frame(width: 720, height: 560)
        .task {
            let crop = viewModel.geometry.crop
            selection = CGRect(x: crop.minX, y: 1 - crop.maxY, width: crop.width, height: crop.height)
            var geometry = viewModel.geometry
            geometry.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
            let engine = viewModel.engine
            let preset = viewModel.currentPreset
            let cg = await Task.detached(priority: .userInitiated) {
                engine.render(with: preset, targetMaxDimension: 1400, geometry: geometry)
            }.value
            if let cg { image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        }
    }
}
