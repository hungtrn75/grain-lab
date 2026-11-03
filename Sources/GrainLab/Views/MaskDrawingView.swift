import SwiftUI

struct MaskDrawingView: View {
    @ObservedObject var viewModel: EditorViewModel
    let canvasSize: CGSize
    let imageSize: CGSize
    @State private var points: [CGPoint] = []
    @State private var drawingLayerID: UUID?

    private func sourcePoint(_ location: CGPoint) -> CGPoint? {
        guard viewModel.sourceImageSize.width > 0, viewModel.sourceImageSize.height > 0,
              let output = CanvasCoordinates.imagePoint(location, canvas: canvasSize, image: imageSize,
                   zoom: viewModel.zoomScale, pan: viewModel.panOffset) else { return nil }
        let source = viewModel.geometry.sourcePoint(fromOutput: output, sourceSize: viewModel.sourceImageSize)
        return CGPoint(x: min(max(source.x, 0), 1), y: min(max(source.y, 0), 1))
    }

    private func canvasPoint(_ source: CGPoint) -> CGPoint {
        let output = viewModel.geometry.outputPoint(fromSource: source, sourceSize: viewModel.sourceImageSize)
        let fit = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height) * viewModel.zoomScale
        return CGPoint(x: canvasSize.width / 2 + viewModel.panOffset.width + (output.x - 0.5) * imageSize.width * fit,
                       y: canvasSize.height / 2 + viewModel.panOffset.height + (output.y - 0.5) * imageSize.height * fit)
    }

    var body: some View {
        ZStack {
            Color.clear
            if let layer = viewModel.selectedLayer, layer.kind != .brush {
                Path { path in
                    let start = canvasPoint(layer.start), end = canvasPoint(layer.end)
                    path.move(to: start); path.addLine(to: end)
                    if layer.kind == .radial {
                        // Four source-axis corners preserve the ellipse guide under rotation.
                        let corners = [CGPoint(x: layer.end.x, y: layer.start.y), CGPoint(x: layer.start.x, y: layer.end.y)]
                        let x = canvasPoint(corners[0]), y = canvasPoint(corners[1])
                        var ellipse = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
                        ellipse = ellipse.applying(CGAffineTransform(a: x.x - start.x, b: x.y - start.y,
                            c: y.x - start.x, d: y.y - start.y, tx: start.x, ty: start.y))
                        path.addPath(ellipse)
                    }
                }.stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).shadow(radius: 2)
                Circle().fill(.white).frame(width: 9, height: 9).position(canvasPoint(layer.start))
                Circle().fill(.white).frame(width: 9, height: 9).position(canvasPoint(layer.end))
            }
            if !points.isEmpty {
                Path { path in
                    path.addLines(points.map(canvasPoint))
                }.stroke(viewModel.brushErase ? .white : .red.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            guard let layer = viewModel.selectedLayer, let point = sourcePoint(value.location) else { return }
            if drawingLayerID != layer.id { points = []; drawingLayerID = layer.id }
            if layer.kind == .brush {
                if points.last.map({ hypot($0.x - point.x, $0.y - point.y) > 0.001 }) ?? true { points.append(point) }
            } else if let start = sourcePoint(value.startLocation) {
                viewModel.updateSelectedLayer { $0.start = start; $0.end = point }
            }
        }.onEnded { _ in
            if viewModel.selectedLayer?.kind == .brush, drawingLayerID == viewModel.selectedLayerID, !points.isEmpty {
                let stroke = BrushStroke(points: points, radius: viewModel.brushRadius, hardness: viewModel.brushHardness,
                                         flow: viewModel.brushFlow, erase: viewModel.brushErase)
                viewModel.updateSelectedLayer { $0.strokes.append(stroke) }
            }
            points = []
            drawingLayerID = nil
        })
        .onHover { inside in if inside { NSCursor.crosshair.set() } else { NSCursor.arrow.set() } }
        .onDisappear { NSCursor.arrow.set() }
    }
}
