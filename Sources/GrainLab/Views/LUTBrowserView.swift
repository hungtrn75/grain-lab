import SwiftUI

@MainActor
final class LUTBrowserModel: ObservableObject {
    @Published var thumbnails: [String: NSImage] = [:]
    @Published var failures: [String: String] = [:]
    @Published var isLoading = false
    @Published var error: String?
    @Published private(set) var completedIntensity: CGFloat?
    private var generation = UUID()
    private var source: CGImage?
    static let bypassID = "__grainlab_bypass__"

    func load(engine: CoreImageEngine, preset: FilmPreset, geometry: PhotoGeometry, items: [LUTItem], layers: [AdjustmentLayer] = []) async {
        let generation = UUID()
        self.generation = generation
        completedIntensity = nil
        isLoading = true
        error = nil
        thumbnails = [:]
        failures = [:]
        defer { if self.generation == generation { isLoading = false } }
        if source == nil {
            let worker = Task.detached(priority: .userInitiated) {
                engine.makeLUTPreviewSource(preset: preset, geometry: geometry)
            }
            source = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
        }
        guard !Task.isCancelled else { return }
        guard let source else { error = "Unable to create image previews."; return }
        // One thumbnail at a time keeps GPU and LUT memory usage bounded.
        for item in [nil] + items.map(Optional.some) {
            guard !Task.isCancelled else { return }
            let id = item?.id ?? Self.bypassID
            let worker = Task.detached(priority: .utility) { () -> (CGImage?, String?) in
                do {
                    let lut = try item.map { try LUTParser.shared.parse(from: $0.url) }
                    guard !Task.isCancelled else { return (nil, nil) }
                    return (engine.renderLUTThumbnail(source: source, preset: preset, lut: lut, layers: layers,
                        sourceExtent: engine.sourceImageSize.map { CGRect(origin: .zero, size: $0) }, geometry: geometry), nil)
                } catch { return (nil, error.localizedDescription) }
            }
            let (image, message) = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            if let image { thumbnails[id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
            else { failures[id] = message ?? "Unable to render this LUT." }
        }
        if !Task.isCancelled, self.generation == generation { completedIntensity = preset.lutIntensity }
    }
}

struct LUTBrowserView: View {
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var registry = LUTRegistry.shared
    @StateObject private var model = LUTBrowserModel()
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection: String
    @State private var intensity: CGFloat
    private let snapshot: FilmPreset
    private let geometry: PhotoGeometry
    private let layers: [AdjustmentLayer]

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        snapshot = viewModel.currentPreset
        geometry = viewModel.geometry
        layers = viewModel.layers
        _selection = State(initialValue: viewModel.currentPreset.lutFileName ?? LUTBrowserModel.bypassID)
        _intensity = State(initialValue: viewModel.currentPreset.lutIntensity)
    }

    private var filtered: [LUTItem] {
        registry.availableLUTs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LUT Browser").font(.title2.bold())
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                TextField("Search LUTs", text: $search).textFieldStyle(.roundedBorder).frame(width: 230)
            }
            Text("Preview on your photo with current color edits, crop and effects. Select a look, then Apply.")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Text("Intensity: \(Int(intensity * 100))%").frame(width: 110, alignment: .leading)
                Slider(value: $intensity, in: 0...1, step: 0.05).frame(width: 240)
                Spacer()
                Text("\(filtered.count) LUTs").foregroundColor(.secondary)
            }.font(.caption)
            if let error = model.error { Text(error).foregroundColor(.red) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    thumbnail(id: LUTBrowserModel.bypassID, name: "None / Bypass")
                    ForEach(filtered) { item in thumbnail(id: item.id, name: item.name) }
                }.padding(4)
                if filtered.isEmpty { Text("No matching LUTs").foregroundColor(.secondary).padding() }
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text(selection == LUTBrowserModel.bypassID ? "None / Bypass" : (registry.availableLUTs.first { $0.id == selection }?.name ?? selection))
                    .font(.caption).lineLimit(1)
                Button("Apply LUT") {
                    viewModel.currentPreset.lutFileName = selection == LUTBrowserModel.bypassID ? nil : selection
                    viewModel.currentPreset.lutIntensity = intensity
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(model.thumbnails[selection] == nil || model.isLoading || model.completedIntensity != intensity)
            }
        }
        .padding(20).frame(width: 800, height: 620)
        .task(id: intensity) {
            // Coalesce slider changes; cancelled tasks stop before the next LUT.
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            var preset = snapshot
            preset.lutIntensity = intensity
            await model.load(engine: viewModel.engine, preset: preset, geometry: geometry, items: registry.availableLUTs, layers: layers)
        }
    }

    private func thumbnail(id: String, name: String) -> some View {
        Button { selection = id } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.black.opacity(0.3)
                    if let image = model.thumbnails[id] {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else if model.failures[id] != nil {
                        Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    } else { ProgressView().controlSize(.small) }
                }
                .frame(height: 125).clipped().cornerRadius(5)
                HStack {
                    Text(name).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if selection == id { Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor) }
                }.frame(height: 30)
            }
            .padding(7)
            .background(selection == id ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == id ? Color.accentColor : .clear, lineWidth: 2))
            .cornerRadius(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.thumbnails[id] == nil)
        .help(model.failures[id] ?? name)
    }
}
