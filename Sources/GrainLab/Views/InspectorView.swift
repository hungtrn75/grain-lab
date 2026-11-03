import SwiftUI
import AppKit

public struct InspectorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @ObservedObject var lutRegistry = LUTRegistry.shared
    
    @State private var showExportSheet = false
    @State private var showLUTBrowser = false
    
    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: - 1. Live Histogram
                HistogramView(
                    luma: viewModel.histogramLuma,
                    red: viewModel.histogramRed,
                    green: viewModel.histogramGreen,
                    blue: viewModel.histogramBlue
                )
                
                Divider()
                
                // MARK: - 2. Basic Adjustments (WB & Exposure)
                GeometryEditorView(viewModel: viewModel)
                Divider()
                basicAdjustmentsSection
                
                Divider()
                
                // MARK: - 3. Tone Curve
                ToneCurveEditorView(points: $viewModel.currentPreset.toneCurvePoints)
                
                Divider()
                
                // MARK: - 4. Film Simulation (3D LUT)
                filmSimulationSection
                
                Divider()
                
                LayersView(viewModel: viewModel)
                Divider()

                // MARK: - 5. Film Grain Effects
                lightEffectsSection
                Divider()
                filmGrainSection
                
                Divider()
                
                // MARK: - 6. Actions (Export & Reset)
                actionsSection
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320)

        .sheet(isPresented: $showLUTBrowser) {
            LUTBrowserView(viewModel: viewModel)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(viewModel: viewModel)
        }
    }
    
    // MARK: - Basic Adjustments Section
    private var basicAdjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BASIC & WHITE BALANCE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Reset") {
                    viewModel.currentPreset.whiteBalanceGains = nil
                    viewModel.currentPreset.temperature = 5500.0
                    viewModel.currentPreset.tint = 0.0
                    viewModel.currentPreset.exposure = 0.0
                    viewModel.currentPreset.contrast = 1.0
                    viewModel.currentPreset.shadows = 0.0
                    viewModel.currentPreset.highlights = 0.0
                }
                .font(.caption2)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            Button { viewModel.toggleWhiteBalancePicker() } label: {
                Label(viewModel.isPickingWhiteBalance ? "Cancel WB Picker (Esc)" : "Pick Neutral Gray / White…", systemImage: "eyedropper")
                    .frame(maxWidth: .infinity)
            }
            .tint(viewModel.isPickingWhiteBalance ? .orange : .accentColor)
            .disabled(viewModel.displayImage == nil || viewModel.isProcessing || viewModel.isSamplingWhiteBalance)
            if viewModel.isSamplingWhiteBalance {
                ProgressView("Measuring neutral area…").controlSize(.small)
            }
            if let message = viewModel.whiteBalanceMessage {
                Text(message).font(.caption2).foregroundColor(.secondary)
            }
            if viewModel.currentPreset.whiteBalanceGains != nil {
                HStack {
                    Text("Sampled WB active").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button("Clear Sample") { viewModel.currentPreset.whiteBalanceGains = nil }.font(.caption2)
                }
            }

            // Temperature (2000K to 10000K)
            sliderRow(
                title: "Temp",
                valueDisplay: "\(Int(viewModel.currentPreset.temperature)) K",
                value: Binding(get: { viewModel.currentPreset.temperature }, set: {
                    viewModel.currentPreset.whiteBalanceGains = nil
                    viewModel.currentPreset.temperature = $0
                }),
                range: 2000...10000,
                step: 25,
                defaultValue: 5500
            )
            
            // Tint (-150 to +150)
            sliderRow(
                title: "Tint",
                valueDisplay: String(format: "%+.0f", viewModel.currentPreset.tint),
                value: Binding(get: { viewModel.currentPreset.tint }, set: {
                    viewModel.currentPreset.whiteBalanceGains = nil
                    viewModel.currentPreset.tint = $0
                }),
                range: -150...150,
                step: 1,
                defaultValue: 0
            )
            
            // Exposure (-3.0 to +3.0 EV)
            sliderRow(
                title: "Exposure",
                valueDisplay: String(format: "%+.2f EV", viewModel.currentPreset.exposure),
                value: $viewModel.currentPreset.exposure,
                range: -3.0...3.0,
                step: 0.05,
                defaultValue: 0.0
            )
            
            // Contrast (0.5 to 2.0)
            sliderRow(
                title: "Contrast",
                valueDisplay: String(format: "%.2f", viewModel.currentPreset.contrast),
                value: $viewModel.currentPreset.contrast,
                range: 0.5...2.0,
                step: 0.01,
                defaultValue: 1.0
            )
            
            // Highlights (-1.0 to 1.0)
            sliderRow(
                title: "Highlights",
                valueDisplay: String(format: "%+.2f", viewModel.currentPreset.highlights),
                value: $viewModel.currentPreset.highlights,
                range: -1.0...1.0,
                step: 0.02,
                defaultValue: 0.0
            )
            
            // Shadows (-1.0 to 1.0)
            sliderRow(
                title: "Shadows",
                valueDisplay: String(format: "%+.2f", viewModel.currentPreset.shadows),
                value: $viewModel.currentPreset.shadows,
                range: -1.0...1.0,
                step: 0.02,
                defaultValue: 0.0
            )
        }
    }
    
    // MARK: - Film Simulation (3D LUT)
    private var filmSimulationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FILM SIMULATION (3D LUT)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                
                Menu {
                    Button("Import & Apply LUT Only…") { importCustomLUT(keepEdits: false) }
                    Button("Import LUT, Keep Current Edits…") { importCustomLUT(keepEdits: true) }
                } label: {
                    Label("Import .cube", systemImage: "plus.circle").font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .foregroundColor(.accentColor)
            }
            
            Button { showLUTBrowser = true } label: {
                Label("Browse LUT Previews…", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.displayImage == nil)

            // LUT Picker
            VStack(alignment: .leading, spacing: 4) {
                Picker("Look", selection: Binding(
                    get: { viewModel.currentPreset.lutFileName ?? "None" },
                    set: { viewModel.currentPreset.lutFileName = ($0 == "None" ? nil : $0) }
                )) {
                    Text("None / Bypass").tag("None")
                    Divider()
                    ForEach(lutRegistry.availableLUTs) { item in
                        Text(item.name).tag(item.fileName)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // LUT Intensity Slider (0.0 to 1.0)
            if let fileName = viewModel.currentPreset.lutFileName {
                Button("Reset Color & Apply LUT at 100%") { viewModel.applyLUTOnly(fileName) }
                    .font(.caption2)
                    .help("Clear WB, exposure, tone curve and grain; keep crop and rotation")
                sliderRow(
                    title: "Intensity",
                    valueDisplay: "\(Int(viewModel.currentPreset.lutIntensity * 100))%",
                    value: $viewModel.currentPreset.lutIntensity,
                    range: 0.0...1.0,
                    step: 0.01,
                    defaultValue: 1.0
                )
            }
        }
    }
    
    private var lightEffectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("HALATION & BLOOM").font(.caption2).fontWeight(.semibold).foregroundColor(.secondary)
                Spacer()
                Button("Reset") { viewModel.currentPreset.lightEffects = nil }.font(.caption2)
            }
            Text("Warm halos around highlights, plus soft light diffusion.")
                .font(.caption2).foregroundColor(.secondary)
            sliderRow(title: "Halation", valueDisplay: "\(Int(viewModel.currentPreset.halationAmount * 100))%",
                      value: $viewModel.currentPreset.halationAmount, range: 0...1, step: 0.01, defaultValue: 0)
            if viewModel.currentPreset.halationAmount > 0 {
                sliderRow(title: "Halo Spread", valueDisplay: String(format: "%.0f", viewModel.currentPreset.halationRadius),
                          value: $viewModel.currentPreset.halationRadius, range: 1...80, step: 1, defaultValue: 12)
            }
            sliderRow(title: "Bloom", valueDisplay: "\(Int(viewModel.currentPreset.bloomAmount * 100))%",
                      value: $viewModel.currentPreset.bloomAmount, range: 0...1, step: 0.01, defaultValue: 0)
            if viewModel.currentPreset.bloomAmount > 0 {
                sliderRow(title: "Bloom Spread", valueDisplay: String(format: "%.0f", viewModel.currentPreset.bloomRadius),
                          value: $viewModel.currentPreset.bloomRadius, range: 1...150, step: 1, defaultValue: 35)
            }
            if viewModel.currentPreset.halationAmount > 0 || viewModel.currentPreset.bloomAmount > 0 {
                sliderRow(title: "Highlight Threshold", valueDisplay: "\(Int(viewModel.currentPreset.lightThreshold * 100))%",
                          value: $viewModel.currentPreset.lightThreshold, range: 0.1...0.95, step: 0.01, defaultValue: 0.6)
                Text("Lower the threshold to include more highlights.").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Film Grain Section
    private var filmGrainSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FILM GRAIN & TEXTURE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.currentPreset.grainIntensity > 0 {
                    Button("Off") {
                        viewModel.currentPreset.grainIntensity = 0.0
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            
            // Grain Intensity (0.0 to 1.0)
            sliderRow(
                title: "Amount",
                valueDisplay: "\(Int(viewModel.currentPreset.grainIntensity * 100))%",
                value: $viewModel.currentPreset.grainIntensity,
                range: 0.0...1.0,
                step: 0.01,
                defaultValue: 0.0
            )
            
            // Grain Size (1.0 to 3.0)
            if viewModel.currentPreset.grainIntensity > 0 {
                sliderRow(
                    title: "Size",
                    valueDisplay: String(format: "%.1f px", viewModel.currentPreset.grainSize),
                    value: $viewModel.currentPreset.grainSize,
                    range: 1.0...3.0,
                    step: 0.1,
                    defaultValue: 1.0
                )
            }
        }
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button(action: { showExportSheet = true }) {
                Label("Export Master Photo...", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.displayImage == nil)
            
            Button("Reset All to Default") {
                viewModel.resetAdjustments()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }
    
    // MARK: - Reusable Slider Row
    private func sliderRow(
        title: String,
        valueDisplay: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        defaultValue: CGFloat
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
                Text(valueDisplay)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step)
                    .controlSize(.mini)
                
                // Double click or option click reset button
                Button(action: { value.wrappedValue = defaultValue }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9))
                        .foregroundColor(value.wrappedValue != defaultValue ? .accentColor : .clear)
                }
                .buttonStyle(.plain)
                .frame(width: 14)
                .help("Reset to default")
            }
        }
    }
    
    // MARK: - Custom LUT Import
    private func importCustomLUT(keepEdits: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cube") ?? .data]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let item = try lutRegistry.importLUT(from: url)
                if keepEdits {
                    viewModel.currentPreset.lutFileName = item.fileName
                } else {
                    viewModel.applyLUTOnly(item.fileName)
                }
            } catch {
                viewModel.errorMessage = "Unable to import LUT: \(error.localizedDescription)"
            }
        }
    }
}
