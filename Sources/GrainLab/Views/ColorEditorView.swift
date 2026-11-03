import SwiftUI

struct ColorEditorView: View {
    @ObservedObject var viewModel: EditorViewModel

    private func value<T>(_ keyPath: WritableKeyPath<ColorRangeAdjustment, T>, fallback: T) -> Binding<T> {
        Binding(get: { viewModel.selectedColorRange?[keyPath: keyPath] ?? fallback },
                set: { value in viewModel.updateColorRange { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable", isOn: Binding(get: { viewModel.currentPreset.colorAdjustments?.enabled ?? true }, set: { enabled in
                    var settings = viewModel.currentPreset.colorAdjustments ?? ColorAdjustments()
                    settings.enabled = enabled
                    viewModel.currentPreset.colorAdjustments = settings
                })).font(.caption)
                Spacer()
                Button("Reset All") {
                    viewModel.currentPreset.colorAdjustments = nil
                    viewModel.selectedColorRangeIndex = 0
                }.font(.caption2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                ForEach(Array(viewModel.colorRanges.enumerated()), id: \.offset) { index, range in
                    Button { viewModel.selectedColorRangeIndex = index } label: {
                        Circle().fill(Color(hue: Double(range.center / 360), saturation: 0.8, brightness: 0.9))
                            .frame(height: 22)
                            .overlay(Circle().stroke(viewModel.selectedColorRangeIndex == index ? Color.primary : .clear, lineWidth: 2).padding(-3))
                            .overlay {
                                if range.isAdjusted { Circle().fill(.white).frame(width: 5, height: 5).offset(y: 5) }
                            }
                    }.buttonStyle(.plain).help(range.name)
                        .accessibilityLabel("Select \(range.name) color range")
                }
            }.padding(3)
            Button { viewModel.toggleColorPicker() } label: {
                Label(viewModel.isPickingColor ? "Cancel Color Picker" : "Pick & Add Color Range…", systemImage: "eyedropper")
                    .frame(maxWidth: .infinity)
            }.disabled(viewModel.isProcessing || viewModel.isSamplingColor)
            if viewModel.isSamplingColor { ProgressView("Sampling color…").controlSize(.small) }
            if let message = viewModel.colorSampleMessage { Text(message).font(.caption2).foregroundColor(.secondary) }
            if let range = viewModel.selectedColorRange {
                HStack {
                    Text(range.name).font(.caption.bold())
                    Spacer()
                    Toggle("Range enabled", isOn: value(\.enabled, fallback: true)).labelsHidden().toggleStyle(.checkbox)
                    if viewModel.selectedColorRangeIndex >= 8 {
                        Button(role: .destructive) {
                            var settings = viewModel.currentPreset.colorAdjustments ?? ColorAdjustments()
                            settings.ranges.remove(at: viewModel.selectedColorRangeIndex)
                            viewModel.currentPreset.colorAdjustments = settings
                            viewModel.selectedColorRangeIndex = 0
                        } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Remove sampled range")
                    }
                }
                hueStrip(range)
                slider("Hue", value: value(\.hue, fallback: 0), range: -60...60, suffix: "°", defaultValue: 0)
                slider("Saturation", value: value(\.saturation, fallback: 0), range: -1...1, scale: 100, suffix: "%", defaultValue: 0)
                slider("Lightness", value: value(\.lightness, fallback: 0), range: -0.5...0.5, scale: 100, suffix: "%", defaultValue: 0)
                Divider()
                slider("Range Center", value: value(\.center, fallback: 0), range: 0...360, suffix: "°")
                slider("Range Width", value: value(\.width, fallback: 35), range: 5...90, suffix: "°", defaultValue: 35)
                slider("Softness", value: value(\.softness, fallback: 0.5), range: 0.01...1, scale: 100, suffix: "%", defaultValue: 0.5)
                Button("Reset This Range") {
                    viewModel.updateColorRange { $0.hue = 0; $0.saturation = 0; $0.lightness = 0; $0.width = 35; $0.softness = 0.5 }
                }.font(.caption2)
            }
            Text("Targets hues across the photo, after the film LUT. Near-neutral colors are protected.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .disabled(viewModel.displayImage == nil)
        .onAppear { if viewModel.selectedColorRange == nil { viewModel.selectedColorRangeIndex = 0 } }
        .onChange(of: viewModel.colorRanges.count) { _ in
            if viewModel.selectedColorRange == nil { viewModel.selectedColorRangeIndex = 0 }
        }
    }

    private func hueStrip(_ range: ColorRangeAdjustment) -> some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for index in 0..<120 {
                    let hue = Float(index) / 120
                    let weight = ColorAdjustmentEngine.weight(hue: hue, saturation: 1, range: range)
                    let color = Color(hue: Double(hue), saturation: 0.9, brightness: 0.9).opacity(0.15 + Double(weight) * 0.85)
                    context.fill(Path(CGRect(x: CGFloat(index) * size.width / 120, y: 0, width: size.width / 120 + 1, height: size.height)), with: .color(color))
                }
                let x = range.center / 360 * size.width
                context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                viewModel.updateColorRange { $0.center = min(max(value.location.x / max(geometry.size.width, 1), 0), 1) * 360 }
            })
        }
        .frame(height: 22).background(.black).cornerRadius(4)
        .help("Drag to set the hue range center; bright colors show the selected range")
    }

    private func slider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, scale: CGFloat = 1,
                        suffix: String = "", defaultValue: CGFloat? = nil) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%+.0f", value.wrappedValue * scale) + suffix).monospacedDigit().foregroundColor(.secondary)
            }.font(.caption)
            HStack {
                Slider(value: value, in: range).controlSize(.small)
                if let defaultValue {
                    Button { value.wrappedValue = defaultValue } label: { Image(systemName: "arrow.counterclockwise").font(.caption2) }
                        .buttonStyle(.plain).help("Reset \(title)")
                }
            }
        }
    }
}
