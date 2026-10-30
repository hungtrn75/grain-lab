import SwiftUI

public struct ToneCurveEditorView: View {
    @Binding var points: [CGPoint]
    
    @State private var activePointIndex: Int? = nil
    
    public init(points: Binding<[CGPoint]>) {
        self._points = points
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TONE CURVE")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Curve presets menu
                Menu {
                    Button("Linear (Reset)") { applyCurvePreset(.linear) }
                    Button("Soft Film S-Curve") { applyCurvePreset(.softSCurve) }
                    Button("Hard Contrast S-Curve") { applyCurvePreset(.hardSCurve) }
                    Button("Matte / Lifted Blacks") { applyCurvePreset(.matte) }
                    Button("High Key") { applyCurvePreset(.highKey) }
                } label: {
                    Label("Presets", systemImage: "slider.horizontal.2.square")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }
            
            // Interactive 2D Curve Editor Box
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                
                ZStack {
                    // Background & Grid lines
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    
                    // Grid 25%, 50%, 75%
                    Path { p in
                        for fraction in [0.25, 0.5, 0.75] {
                            let x = w * fraction
                            let y = h * fraction
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                    
                    // Diagonal reference line (neutral 45 deg)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h))
                        p.addLine(to: CGPoint(x: w, y: 0))
                    }
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    // Tone Curve Path
                    curvePath(width: w, height: h)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange, Color.yellow],
                                startPoint: .bottomLeading,
                                endPoint: .topTrailing
                            ),
                            lineWidth: 2
                        )
                    
                    // Control Point Handles (5 points)
                    ForEach(0..<min(points.count, 5), id: \.self) { idx in
                        let pt = points[idx]
                        let screenX = pt.x * w
                        let screenY = (1.0 - pt.y) * h
                        
                        Circle()
                            .fill(activePointIndex == idx ? Color.white : Color.orange)
                            .frame(width: activePointIndex == idx ? 12 : 9, height: activePointIndex == idx ? 12 : 9)
                            .shadow(radius: 2)
                            .position(x: screenX, y: screenY)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        activePointIndex = idx
                                        updatePoint(at: idx, location: value.location, width: w, height: h)
                                    }
                                    .onEnded { _ in
                                        activePointIndex = nil
                                    }
                            )
                    }
                }
            }
            .frame(height: 140)
            
            // Point information / coordinate labels
            HStack {
                Text("Blacks")
                Spacer()
                Text("Shadows")
                Spacer()
                Text("Mid")
                Spacer()
                Text("Highlights")
                Spacer()
                Text("Whites")
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Path Generator
    private func curvePath(width: CGFloat, height: CGFloat) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        
        let screenPoints = points.map { pt in
            CGPoint(x: pt.x * width, y: (1.0 - pt.y) * height)
        }
        
        path.move(to: screenPoints[0])
        
        // Approximate smooth curve through points
        for i in 0..<screenPoints.count - 1 {
            let p0 = screenPoints[max(i - 1, 0)]
            let p1 = screenPoints[i]
            let p2 = screenPoints[i + 1]
            let p3 = screenPoints[min(i + 2, screenPoints.count - 1)]
            
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6.0,
                y: p1.y + (p2.y - p0.y) / 6.0
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6.0,
                y: p2.y - (p3.y - p1.y) / 6.0
            )
            
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        
        return path
    }
    
    // MARK: - Point Adjustment
    private func updatePoint(at index: Int, location: CGPoint, width: CGFloat, height: CGFloat) {
        guard index < points.count else { return }
        
        // Clamp normalized values
        let normalizedY = min(max(1.0 - (location.y / height), 0.0), 1.0)
        
        // Allow modifying Y freely while constraining X to prevent inverted curves
        var current = points[index]
        current.y = normalizedY
        
        if index > 0 && index < points.count - 1 {
            let minX = points[index - 1].x + 0.05
            let maxX = points[index + 1].x - 0.05
            let normalizedX = min(max(location.x / width, minX), maxX)
            current.x = normalizedX
        }
        
        points[index] = current
    }
    
    // MARK: - Curve Presets
    enum CurvePreset {
        case linear
        case softSCurve
        case hardSCurve
        case matte
        case highKey
    }
    
    private func applyCurvePreset(_ preset: CurvePreset) {
        switch preset {
        case .linear:
            points = [
                CGPoint(x: 0.0, y: 0.0),
                CGPoint(x: 0.25, y: 0.25),
                CGPoint(x: 0.50, y: 0.50),
                CGPoint(x: 0.75, y: 0.75),
                CGPoint(x: 1.0, y: 1.0)
            ]
        case .softSCurve:
            points = [
                CGPoint(x: 0.0, y: 0.0),
                CGPoint(x: 0.25, y: 0.22),
                CGPoint(x: 0.50, y: 0.50),
                CGPoint(x: 0.75, y: 0.78),
                CGPoint(x: 1.0, y: 1.0)
            ]
        case .hardSCurve:
            points = [
                CGPoint(x: 0.0, y: 0.0),
                CGPoint(x: 0.25, y: 0.17),
                CGPoint(x: 0.50, y: 0.50),
                CGPoint(x: 0.75, y: 0.83),
                CGPoint(x: 1.0, y: 1.0)
            ]
        case .matte:
            points = [
                CGPoint(x: 0.0, y: 0.08),
                CGPoint(x: 0.25, y: 0.24),
                CGPoint(x: 0.50, y: 0.49),
                CGPoint(x: 0.75, y: 0.76),
                CGPoint(x: 1.0, y: 0.95)
            ]
        case .highKey:
            points = [
                CGPoint(x: 0.0, y: 0.04),
                CGPoint(x: 0.25, y: 0.32),
                CGPoint(x: 0.50, y: 0.60),
                CGPoint(x: 0.75, y: 0.82),
                CGPoint(x: 1.0, y: 1.0)
            ]
        }
    }
}
