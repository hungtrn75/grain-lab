import SwiftUI
import UniformTypeIdentifiers

struct LayersView: View {
    @ObservedObject var viewModel: EditorViewModel

    private func value<T>(_ keyPath: WritableKeyPath<AdjustmentLayer, T>, fallback: T) -> Binding<T> {
        Binding(get: { viewModel.selectedLayer?[keyPath: keyPath] ?? fallback },
                set: { value in viewModel.updateSelectedLayer { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LAYERS & MASKS").font(.caption2.bold()).foregroundColor(.secondary)
                Spacer()
                Menu {
                    Button("Import Layers…") { importLayers() }
                    Button("Export Layers…") { exportLayers() }.disabled(viewModel.layers.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                Menu {
                    ForEach(LayerMaskKind.allCases) { kind in
                        Button(kind.rawValue) { viewModel.addLayer(kind) }
                    }
                } label: { Label("Add", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
            }
            if viewModel.layers.isEmpty {
                Text("Add a gradient or brush layer for local adjustments.").font(.caption2).foregroundColor(.secondary)
            }
            ForEach(viewModel.layers.reversed()) { layer in
                HStack(spacing: 6) {
                    Toggle("Enable layer", isOn: Binding(get: {
                        viewModel.layers.first { $0.id == layer.id }?.enabled ?? false
                    }, set: { enabled in
                        if let index = viewModel.layers.firstIndex(where: { $0.id == layer.id }) { viewModel.layers[index].enabled = enabled }
                    })).labelsHidden().toggleStyle(.checkbox)
                    Button {
                        viewModel.selectedLayerID = layer.id
                    } label: {
                        HStack {
                            Image(systemName: layer.kind == .brush ? "paintbrush.pointed" : "circle.lefthalf.filled")
                            Text(layer.name).lineLimit(1)
                            Spacer()
                            if viewModel.selectedLayerID == layer.id { Image(systemName: "checkmark") }
                        }.font(.caption).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(6).background(viewModel.selectedLayerID == layer.id ? Color.accentColor.opacity(0.15) : .clear).cornerRadius(5)
            }
            if let layer = viewModel.selectedLayer {
                TextField("Layer name", text: value(\.name, fallback: "Layer")).textFieldStyle(.roundedBorder)
                HStack {
                    Button(viewModel.isEditingMask ? "Done Drawing" : "Draw / Edit Mask") { viewModel.isEditingMask.toggle() }
                    Spacer()
                    Button { viewModel.moveSelectedLayer(1) } label: { Image(systemName: "arrow.up") }.help("Move layer up")
                    Button { viewModel.moveSelectedLayer(-1) } label: { Image(systemName: "arrow.down") }.help("Move layer down")
                    Button(role: .destructive) { viewModel.deleteSelectedLayer() } label: { Image(systemName: "trash") }.help("Delete layer")
                }.controlSize(.small)
                Toggle("Show red mask overlay", isOn: $viewModel.showMaskOverlay).font(.caption)
                Toggle("Invert mask", isOn: value(\.inverted, fallback: false)).font(.caption)
                slider("Layer Opacity", binding: value(\.opacity, fallback: 1), range: 0...1)
                if layer.kind == .radial {
                    slider("Feather", binding: value(\.feather, fallback: 0.5), range: 0.01...1)
                }
                if layer.kind == .brush {
                    Toggle("Erase", isOn: $viewModel.brushErase).font(.caption)
                    slider("Brush Size", binding: $viewModel.brushRadius, range: 0.005...0.2)
                    slider("Hardness", binding: $viewModel.brushHardness, range: 0...0.99)
                    slider("Flow", binding: $viewModel.brushFlow, range: 0.05...1)
                    HStack {
                        Button("Undo Stroke") { viewModel.updateSelectedLayer { if !$0.strokes.isEmpty { $0.strokes.removeLast() } } }
                            .disabled(layer.strokes.isEmpty)
                        Button("Clear Mask") { viewModel.updateSelectedLayer { $0.strokes = [] } }.disabled(layer.strokes.isEmpty)
                    }.font(.caption)
                }
                Text(layer.kind == .linear ? "Drag from full effect to no effect. Drag again to reposition." :
                     layer.kind == .radial ? "Drag from the center to the ellipse edge. Drag again to reposition." :
                     "Paint on the image. Use Erase to remove areas; Done Drawing restores pan.")
                    .font(.caption2).foregroundColor(.secondary)
                Divider()
                slider("Exposure (EV)", binding: value(\.exposure, fallback: 0), range: -3...3)
                slider("Contrast", binding: value(\.contrast, fallback: 1), range: 0.5...2)
                slider("Saturation", binding: value(\.saturation, fallback: 1), range: 0...2)
                slider("Warmth", binding: value(\.warmth, fallback: 0), range: -2500...2500)
                Button("Reset Layer Adjustments") {
                    viewModel.updateSelectedLayer { $0.exposure = 0; $0.contrast = 1; $0.saturation = 1; $0.warmth = 0 }
                }.font(.caption2)
            }
        }
        .disabled(viewModel.displayImage == nil)
    }

    private func exportLayers() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = (viewModel.loadedImageURL?.deletingPathExtension().lastPathComponent ?? "Photo") + "_layers.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(LayerArchive(layers: viewModel.layers)).write(to: url, options: .atomic)
        } catch { viewModel.errorMessage = error.localizedDescription }
    }

    private func importLayers() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var imported = try LayerArchive.decode(Data(contentsOf: url))
            for index in imported.indices { imported[index].id = UUID() }
            viewModel.layers.append(contentsOf: imported)
            viewModel.selectedLayerID = imported.last?.id ?? viewModel.selectedLayerID
            viewModel.isEditingMask = !imported.isEmpty
        } catch { viewModel.errorMessage = error.localizedDescription }
    }

    private func slider(_ title: String, binding: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: abs(range.upperBound) > 10 ? "%.0f" : "%.2f", binding.wrappedValue)).monospacedDigit().foregroundColor(.secondary)
            }.font(.caption)
            Slider(value: binding, in: range).controlSize(.small)
        }
    }
}
