import Foundation

public struct LUTItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let fileName: String
    public let url: URL
    
    public init(name: String, fileName: String, url: URL) {
        self.id = fileName
        self.name = name
        self.fileName = fileName
        self.url = url
    }
}

public final class LUTRegistry: ObservableObject {
    public static let shared = LUTRegistry()
    
    @Published public private(set) var availableLUTs: [LUTItem] = []
    
    private let fileManager = FileManager.default
    
    public var lutsDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GrainLab/LUTs", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    public init() {
        installDefaultLUTsIfNeeded()
        reloadLUTs()
    }
    
    public func reloadLUTs() {
        var items: [LUTItem] = []
        
        // 1. Check bundle resources
        if let resourcePath = Bundle.module.resourcePath,
           let files = try? fileManager.contentsOfDirectory(atPath: resourcePath) {
            for file in files where file.hasSuffix(".cube") {
                let url = URL(fileURLWithPath: resourcePath).appendingPathComponent(file)
                let name = (file as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
                items.append(LUTItem(name: name, fileName: file, url: url))
            }
        }
        
        // 2. Check application support LUTs directory
        if let appSupportFiles = try? fileManager.contentsOfDirectory(at: lutsDirectoryURL, includingPropertiesForKeys: nil) {
            for fileURL in appSupportFiles where fileURL.pathExtension.lowercased() == "cube" {
                let fileName = fileURL.lastPathComponent
                items.removeAll { $0.fileName == fileName }
                do {
                    let name = fileURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                    items.append(LUTItem(name: name, fileName: fileName, url: fileURL))
                }
            }
        }
        
        self.availableLUTs = items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
    
    public func resolveURL(for fileName: String) -> URL? {
        if let item = availableLUTs.first(where: { $0.fileName == fileName }) {
            return item.url
        }
        
        let localURL = lutsDirectoryURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }
        
        if let bundleURL = Bundle.module.url(forResource: (fileName as NSString).deletingPathExtension, withExtension: "cube") {
            return bundleURL
        }
        
        return nil
    }
    
    /// Imports a user-selected .cube file into the local LUTs directory
    @discardableResult
    public func importLUT(from sourceURL: URL) throws -> LUTItem {
        let fileName = sourceURL.lastPathComponent
        let targetURL = lutsDirectoryURL.appendingPathComponent(fileName)
        
        // Validate before replacing a working LUT, and replace atomically.
        let data = try Data(contentsOf: sourceURL)
        guard let content = String(data: data, encoding: .utf8) else {
            throw LUTError.unsupportedFormat
        }
        _ = try LUTParser.shared.parse(string: content)
        try data.write(to: targetURL, options: .atomic)
        LUTParser.shared.invalidate(url: targetURL)
        reloadLUTs()
        
        let name = targetURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        return LUTItem(name: name, fileName: fileName, url: targetURL)
    }
    
    // MARK: - Default Film LUTs Generation
    private func installDefaultLUTsIfNeeded() {
        let defaults: [(fileName: String, title: String, transform: (Float, Float, Float) -> (Float, Float, Float))] = [
            (
                fileName: "Kodak_Portra_400.cube",
                title: "Kodak Portra 400",
                transform: { r, g, b in
                    // Warm skin tones, softened highlights, slightly elevated shadows
                    var nr = pow(r, 0.95) * 1.04
                    let ng = pow(g, 0.98) * 0.99
                    var nb = pow(b, 1.05) * 0.93
                    // Warm golden shadow cast
                    nr += 0.02 * (1.0 - r)
                    nb -= 0.01 * (1.0 - b)
                    return (min(max(nr, 0), 1), min(max(ng, 0), 1), min(max(nb, 0), 1))
                }
            ),
            (
                fileName: "Fuji_Pro_400H.cube",
                title: "Fujifilm Pro 400H",
                transform: { r, g, b in
                    // Cooler cyan-green shadows, pastel airy highlights, lifted blacks
                    var nr = pow(r, 1.04) * 0.97
                    var ng = pow(g, 0.97) * 1.02
                    var nb = pow(b, 0.95) * 1.03
                    // Pastel lifted blacks
                    nr = nr * 0.94 + 0.03
                    ng = ng * 0.94 + 0.04
                    nb = nb * 0.94 + 0.05
                    return (min(max(nr, 0), 1), min(max(ng, 0), 1), min(max(nb, 0), 1))
                }
            ),
            (
                fileName: "Ilford_HP5_Plus.cube",
                title: "Ilford HP5 Plus (B&W)",
                transform: { r, g, b in
                    // Authentic panchromatic B&W response curve
                    let luma = 0.299 * r + 0.587 * g + 0.114 * b
                    // Film S-curve for punchy silver gelatin look
                    let s = luma * luma * (3.0 - 2.0 * luma)
                    let toned = pow(s, 1.05)
                    return (toned, toned, toned)
                }
            ),
            (
                fileName: "Cinestill_800T.cube",
                title: "CineStill 800T",
                transform: { r, g, b in
                    // Tungsten balanced: deep cool blue shadows, rich warm amber lights
                    var nr = pow(r, 1.1) * 1.08
                    let ng = pow(g, 1.0) * 0.96
                    let nb = pow(b, 0.92) * 1.06
                    // Halation glow in highlights
                    if r > 0.7 { nr += (r - 0.7) * 0.2 }
                    return (min(max(nr, 0), 1), min(max(ng, 0), 1), min(max(nb, 0), 1))
                }
            ),
            (
                fileName: "Kodachrome_64.cube",
                title: "Kodachrome 64 Vintage",
                transform: { r, g, b in
                    // Iconic high-saturation, punchy contrast, warm saturated reds & yellows
                    var nr = pow(r, 1.15) * 1.10
                    var ng = pow(g, 1.10) * 1.02
                    var nb = pow(b, 1.25) * 0.95
                    nr = min(max(nr, 0), 1)
                    ng = min(max(ng, 0), 1)
                    nb = min(max(nb, 0), 1)
                    return (nr, ng, nb)
                }
            )
        ]
        
        let dim = 17 // 17x17x17 is standard fast 3D LUT size (~50KB each)
        for item in defaults {
            let targetURL = lutsDirectoryURL.appendingPathComponent(item.fileName)
            if !fileManager.fileExists(atPath: targetURL.path) {
                if let content = generateCubeContent(dim: dim, title: item.title, transform: item.transform) {
                    try? content.write(to: targetURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }
    
    private func generateCubeContent(
        dim: Int,
        title: String,
        transform: (Float, Float, Float) -> (Float, Float, Float)
    ) -> String? {
        var str = "# Created by GrainLab Film Engine\n"
        str += "TITLE \"\(title)\"\n"
        str += "LUT_3D_SIZE \(dim)\n"
        str += "DOMAIN_MIN 0.0 0.0 0.0\n"
        str += "DOMAIN_MAX 1.0 1.0 1.0\n\n"
        
        for b in 0..<dim {
            let blueVal = Float(b) / Float(dim - 1)
            for g in 0..<dim {
                let greenVal = Float(g) / Float(dim - 1)
                for r in 0..<dim {
                    let redVal = Float(r) / Float(dim - 1)
                    let (tr, tg, tb) = transform(redVal, greenVal, blueVal)
                    str += String(format: "%.6f %.6f %.6f\n", tr, tg, tb)
                }
            }
        }
        return str
    }
}
