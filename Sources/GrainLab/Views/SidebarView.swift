import SwiftUI
import UniformTypeIdentifiers

public struct SidebarView: View {
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var presetManager = PresetManager.shared
    
    @State private var showingSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var isShowingDeleteAlert = false
    @State private var presetToDelete: FilmPreset? = nil
    
    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        List {
            // MARK: - Import / File Section
            Section {
                Button(action: openFilePicker) {
                    Label("Import RAW / Photo", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                if let url = viewModel.loadedImageURL {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("SOURCE IMAGE")
            }
            
            // MARK: - Built-in Film Simulation Presets
            Section {
                ForEach(FilmPreset.builtInPresets) { preset in
                    PresetRow(
                        name: preset.name,
                        icon: filmStockIcon(for: preset.name),
                        isSelected: viewModel.currentPreset.name == preset.name,
                        action: {
                            viewModel.applyPreset(preset)
                        }
                    )
                }
            } header: {
                Text("FILM STOCKS")
            }
            
            // MARK: - User Presets
            Section {
                HStack {
                    Text("MY PRESETS")
                    Spacer()
                    Button(action: {
                        newPresetName = "My Film \(presetManager.userPresets.count + 1)"
                        showingSavePresetDialog = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Save current adjustments as new preset")
                    
                    Menu {
                        Button("Import Preset JSON...") { importPresetFile() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)
                }
                
                if presetManager.userPresets.isEmpty {
                    Text("No saved presets yet.\nClick + to save your edits.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(presetManager.userPresets) { preset in
                        HStack {
                            PresetRow(
                                name: preset.name,
                                icon: "camera.filters",
                                isSelected: viewModel.currentPreset.name == preset.name,
                                action: {
                                    viewModel.applyPreset(preset)
                                }
                            )
                            
                            Spacer()
                            
                            // Contextual Menu
                            Menu {
                                Button("Export JSON...") { exportPresetFile(preset) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    presetToDelete = preset
                                    isShowingDeleteAlert = true
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundColor(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 14)
                        }
                    }
                }
            }
            
            // MARK: - Image EXIF Metadata
            if let meta = viewModel.metadata {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        if meta.isRAW {
                            Label("RAW Sensor Image", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        
                        metadataRow(label: "Dimensions", value: "\(meta.width) × \(meta.height) px")
                        
                        if let camera = meta.cameraModel {
                            metadataRow(label: "Camera", value: camera)
                        }
                        if let lens = meta.lensModel {
                            metadataRow(label: "Lens", value: lens)
                        }
                        
                        HStack(spacing: 8) {
                            if let iso = meta.iso {
                                exifPill("ISO \(iso)")
                            }
                            if let shutter = meta.shutterSpeed {
                                exifPill(shutter)
                            }
                            if let f = meta.aperture {
                                exifPill(f)
                            }
                            if let fl = meta.focalLength {
                                exifPill(fl)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("METADATA & EXIF")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRAWFileRequested)) { _ in
            openFilePicker()
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, idealWidth: 250)
        .sheet(isPresented: $showingSavePresetDialog) {
            savePresetSheet
        }
        .alert("Delete Preset", isPresented: $isShowingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let p = presetToDelete {
                    try? presetManager.deletePreset(p)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(presetToDelete?.name ?? "")'?")
        }
    }
    
    // MARK: - Save Preset Sheet
    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Preset")
                .font(.headline)
            
            TextField("Preset Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
            
            HStack {
                Button("Cancel") { showingSavePresetDialog = false }
                Spacer()
                Button("Save") {
                    var preset = viewModel.currentPreset
                    preset.id = UUID()
                    preset.name = newPresetName.trimmingCharacters(in: .whitespaces)
                    _ = try? presetManager.savePreset(preset)
                    viewModel.currentPreset = preset
                    showingSavePresetDialog = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
    
    // MARK: - File Actions
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        // Allow all RAW formats and common image formats
        let allowedTypes: [UTType] = [
            .rawImage,
            .image,
            UTType(filenameExtension: "nef") ?? .image,
            UTType(filenameExtension: "cr2") ?? .image,
            UTType(filenameExtension: "cr3") ?? .image,
            UTType(filenameExtension: "arw") ?? .image,
            UTType(filenameExtension: "dng") ?? .image,
            UTType(filenameExtension: "raf") ?? .image,
            UTType(filenameExtension: "rw2") ?? .image,
            UTType(filenameExtension: "orf") ?? .image,
            .jpeg,
            .png,
            .tiff
        ]
        panel.allowedContentTypes = allowedTypes
        
        if panel.runModal() == .OK {
            viewModel.importPhotos(panel.urls)
        }
    }
    
    private func importPresetFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            if let preset = try? presetManager.importPreset(from: url) {
                viewModel.applyPreset(preset)
            }
        }
    }
    
    private func exportPresetFile(_ preset: FilmPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(preset.name).json"
        if panel.runModal() == .OK, let url = panel.url {
            try? presetManager.exportPreset(preset, to: url)
        }
    }
    
    // MARK: - UI Subviews & Helpers
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
    
    private func exifPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(4)
    }
    
    private func filmStockIcon(for name: String) -> String {
        if name.contains("Chrome") { return "newspaper.fill" }
        if name.contains("Gold") { return "sun.dust.fill" }
        if name.contains("Color Pro") { return "camera.aperture" }
        if name.contains("Portra") { return "sun.max.fill" }
        if name.contains("Pro") { return "leaf.fill" }
        if name.contains("HP5") || name.contains("B&W") { return "circle.lefthalf.filled" }
        if name.contains("CineStill") { return "moon.stars.fill" }
        if name.contains("Kodachrome") { return "film" }
        return "slider.horizontal.3"
    }
}

// MARK: - Preset Row
private struct PresetRow: View {
    let name: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                
                Text(name)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
