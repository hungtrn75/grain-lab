import CoreGraphics

/// Converts a canvas click through aspect-fit, zoom and pan to top-left image coordinates.
enum CanvasCoordinates {
    static func imagePoint(_ point: CGPoint, canvas: CGSize, image: CGSize, zoom: CGFloat, pan: CGSize) -> CGPoint? {
        guard canvas.width > 0, canvas.height > 0, image.width > 0, image.height > 0, zoom > 0 else { return nil }
        let fit = min(canvas.width / image.width, canvas.height / image.height)
        let width = image.width * fit * zoom
        let height = image.height * fit * zoom
        let x = (point.x - canvas.width / 2 - pan.width) / width + 0.5
        let y = (point.y - canvas.height / 2 - pan.height) / height + 0.5
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }
}
