import Foundation
import CoreImage

/// Represents parsed 3D LUT data ready to be passed to `CIColorCube`
public struct LUTData {
    public let dimension: Int
    public let data: Data
    public let title: String?
    
    public init(dimension: Int, data: Data, title: String? = nil) {
        self.dimension = dimension
        self.data = data
        self.title = title
    }
}

/// Fast parser and in-memory cache for Adobe .cube 3D LUT files
public final class LUTParser {
    public static let shared = LUTParser()
    
    private var cache = NSCache<NSString, NSData>()
    private var dimensionCache: [String: Int] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    /// Parses a .cube file from the specified URL and returns a `LUTData` object.
    /// Results are cached in memory for high rendering performance.
    public func parse(from url: URL) throws -> LUTData {
        let key = url.standardizedFileURL.path
        
        lock.lock()
        if let cachedData = cache.object(forKey: key as NSString),
           let dim = dimensionCache[key] {
            lock.unlock()
            return LUTData(dimension: dim, data: cachedData as Data)
        }
        lock.unlock()
        
        let content = try String(contentsOf: url, encoding: .utf8)
        let lutData = try parse(string: content)
        
        lock.lock()
        cache.setObject(lutData.data as NSData, forKey: key as NSString)
        dimensionCache[key] = lutData.dimension
        lock.unlock()
        
        return lutData
    }
    
    /// Parses a .cube string content directly
    public func parse(string: String) throws -> LUTData {
        var dimension: Int?
        var title: String?
        var floatBuffer: [Float] = []
        
        let lines = string.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            let parts = trimmed.split(separator: " ").map { String($0) }
            guard !parts.isEmpty else { continue }
            
            if parts[0] == "TITLE" {
                title = parts.dropFirst().joined(separator: " ").replacingOccurrences(of: "\"", with: "")
                continue
            }
            
            if parts[0] == "LUT_3D_SIZE" {
                if parts.count >= 2, let dim = Int(parts[1]) {
                    dimension = dim
                    floatBuffer.reserveCapacity(dim * dim * dim * 4)
                }
                continue
            }
            
            // Ignore 1D size, domain min/max lines for now
            if parts[0].hasPrefix("DOMAIN_") || parts[0] == "LUT_1D_SIZE" {
                continue
            }
            
            // Data lines contain 3 floats: R G B
            if parts.count >= 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                floatBuffer.append(r)
                floatBuffer.append(g)
                floatBuffer.append(b)
                floatBuffer.append(1.0) // Premultiplied Alpha
            }
        }
        
        guard let dim = dimension, dim >= 2 else {
            throw LUTError.invalidDimension
        }
        
        let expectedCount = dim * dim * dim * 4
        guard floatBuffer.count == expectedCount else {
            throw LUTError.dataCountMismatch(expected: expectedCount, actual: floatBuffer.count)
        }
        
        let data = floatBuffer.withUnsafeBufferPointer { Data(buffer: $0) }
        return LUTData(dimension: dim, data: data, title: title)
    }
    
    /// Generates identity LUT data of specified dimension
    public static func identity(dimension: Int = 16) -> LUTData {
        var floatBuffer: [Float] = []
        floatBuffer.reserveCapacity(dimension * dimension * dimension * 4)
        
        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    floatBuffer.append(Float(r) / Float(dimension - 1))
                    floatBuffer.append(Float(g) / Float(dimension - 1))
                    floatBuffer.append(Float(b) / Float(dimension - 1))
                    floatBuffer.append(1.0)
                }
            }
        }
        
        let data = floatBuffer.withUnsafeBufferPointer { Data(buffer: $0) }
        return LUTData(dimension: dimension, data: data, title: "Identity")
    }
}

public enum LUTError: LocalizedError {
    case invalidDimension
    case dataCountMismatch(expected: Int, actual: Int)
    case fileNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidDimension:
            return "Invalid or missing LUT_3D_SIZE in .cube file"
        case .dataCountMismatch(let expected, let actual):
            return "LUT data count mismatch. Expected \(expected) floats, got \(actual)"
        case .fileNotFound(let name):
            return "LUT file not found: \(name)"
        }
    }
}
