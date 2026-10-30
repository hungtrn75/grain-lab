import Foundation
import Combine

/// Manager responsible for persisting, loading, importing, and exporting `FilmPreset` instances as JSON.
public final class PresetManager: ObservableObject {
    public static let shared = PresetManager()
    
    @Published public private(set) var userPresets: [FilmPreset] = []
    
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    private let decoder = JSONDecoder()
    
    /// Directory where user custom presets are saved
    public var presetsDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GrainLab/Presets", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    public init() {
        reloadPresets()
    }
    
    /// Reloads all custom presets from the presets directory
    public func reloadPresets() {
        do {
            let files = try fileManager.contentsOfDirectory(at: presetsDirectoryURL, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension.lowercased() == "json" }
            
            var loaded: [FilmPreset] = []
            for file in jsonFiles {
                if let data = try? Data(contentsOf: file),
                   let preset = try? decoder.decode(FilmPreset.self, from: data) {
                    loaded.append(preset)
                }
            }
            self.userPresets = loaded.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        } catch {
            print("[PresetManager] Failed to read presets directory: \(error)")
            self.userPresets = []
        }
    }
    
    /// Saves a preset to disk in the user presets directory
    @discardableResult
    public func savePreset(_ preset: FilmPreset) throws -> URL {
        let sanitizedName = preset.name.replacingOccurrences(of: "/", with: "-")
        let destination = presetsDirectoryURL.appendingPathComponent("\(sanitizedName).json")
        let data = try encoder.encode(preset)
        try data.write(to: destination, options: .atomic)
        reloadPresets()
        return destination
    }
    
    /// Deletes a preset from the user presets directory
    public func deletePreset(_ preset: FilmPreset) throws {
        let sanitizedName = preset.name.replacingOccurrences(of: "/", with: "-")
        let destination = presetsDirectoryURL.appendingPathComponent("\(sanitizedName).json")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        reloadPresets()
    }
    
    /// Imports a preset from an external file URL and saves it to the library
    @discardableResult
    public func importPreset(from sourceURL: URL) throws -> FilmPreset {
        let data = try Data(contentsOf: sourceURL)
        let preset = try decoder.decode(FilmPreset.self, from: data)
        try savePreset(preset)
        return preset
    }
    
    /// Exports a preset to an external destination URL
    public func exportPreset(_ preset: FilmPreset, to destinationURL: URL) throws {
        let data = try encoder.encode(preset)
        try data.write(to: destinationURL, options: .atomic)
    }
    
    /// Decodes a preset from a given URL without saving it
    public func loadPreset(from url: URL) throws -> FilmPreset {
        let data = try Data(contentsOf: url)
        return try decoder.decode(FilmPreset.self, from: data)
    }
}
