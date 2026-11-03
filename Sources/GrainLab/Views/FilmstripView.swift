import SwiftUI
import ImageIO

struct FilmstripView: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(viewModel.photoURLs.count) photos").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Copy Edits") { viewModel.copyAdjustments() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(viewModel.displayImage == nil)
                Button("Paste Edits") { viewModel.pasteAdjustments() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                    .disabled(viewModel.copiedAdjustments == nil || viewModel.displayImage == nil)
                Button("Paste to All") { viewModel.pasteAdjustmentsToAll() }
                    .disabled(viewModel.copiedAdjustments == nil || viewModel.photoURLs.isEmpty)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(viewModel.photoURLs, id: \.self) { url in
                        Button { viewModel.loadImage(from: url) } label: {
                            VStack(spacing: 4) {
                                PhotoThumbnail(url: url)
                                Text(url.lastPathComponent).font(.caption2).lineLimit(1).frame(width: 100)
                            }
                            .padding(5)
                            .background(viewModel.loadedImageURL == url ? Color.accentColor.opacity(0.2) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(viewModel.loadedImageURL == url ? Color.accentColor : Color.clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(url.lastPathComponent)
                    }
                }.padding(3)
            }
        }
        .padding(10)
        .background(.bar)
    }
}

private struct PhotoThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundColor(.secondary) }
        }
        .frame(width: 100, height: 64)
        .task(id: url) {
            let url = url
            let cgImage = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 200
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled, let cgImage else { return }
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}
