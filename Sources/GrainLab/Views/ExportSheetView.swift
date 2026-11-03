import SwiftUI
import AppKit

public struct ExportSheetView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var format: ExportFormat = .jpeg
    @State private var quality: Double = 0.95
    @State private var isExporting = false
    @State private var errorMessage: String? = nil
    
    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Export Master Photo")
                    .font(.headline)
                Spacer()
                if isExporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            
            Divider()
            
            // Format Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("File Format")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $format) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Text(fmt.rawValue).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Quality slider for JPEG
            if format == .jpeg {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Compression Quality")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(quality * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    Slider(value: $quality, in: 0.5...1.0, step: 0.05)
                }
            }
            
            // Output Info
            if let meta = viewModel.metadata {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Target Resolution")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Source: \(meta.width) × \(meta.height) px. Export uses full resolution with the current crop and rotation.")
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            // Bottom Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save As...") {
                    triggerSavePanel()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .padding(20)
        .frame(width: 380, height: 320)
    }
    
    private func triggerSavePanel() {
        let panel = NSSavePanel()
        let originalName = viewModel.loadedImageURL?.deletingPathExtension().lastPathComponent ?? "Edited_Photo"
        panel.nameFieldStringValue = "\(originalName)_\(viewModel.currentPreset.name.replacingOccurrences(of: " ", with: "_")).\(format.fileExtension)"
        
        if panel.runModal() == .OK, let destinationURL = panel.url {
            isExporting = true
            Task {
                do {
                    try await viewModel.exportImage(to: destinationURL, format: format, quality: CGFloat(quality))
                    await MainActor.run {
                        self.isExporting = false
                        self.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Export failed: \(error.localizedDescription)"
                        self.isExporting = false
                    }
                }
            }
        }
    }
}
