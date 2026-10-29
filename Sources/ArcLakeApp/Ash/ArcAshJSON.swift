import Foundation
import CoreGraphics

// ═══════════════════════════════════════════════════════════════════
// ArcJSON — lossless, Codable "JSON-ish" value used by the .ash project
// format. Every module stores its state as ArcJSON so that unknown
// modules / unknown fields written by a newer app version survive a
// round trip through an older one untouched (forward compatibility).
// ═══════════════════════════════════════════════════════════════════

public enum ArcJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ArcJSON])
    case object([String: ArcJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // Number BEFORE bool: some Foundation versions will happily decode
        // the JSON numbers 0/1 as Bool, but never decode true/false as Double.
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([ArcJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: ArcJSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:            try c.encodeNil()
        case .bool(let b):     try c.encode(b)
        case .number(let d):   try c.encode(d.isFinite ? d : 0)
        case .string(let s):   try c.encode(s)
        case .array(let a):    try c.encode(a)
        case .object(let o):   try c.encode(o)
        }
    }

    // MARK: — Builders
    public static func n(_ v: Double) -> ArcJSON { .number(v.isFinite ? v : 0) }
    public static func n(_ v: Float) -> ArcJSON { .number(v.isFinite ? Double(v) : 0) }
    public static func n(_ v: Int) -> ArcJSON { .number(Double(v)) }
    public static func n(_ v: CGFloat) -> ArcJSON { .number(v.isFinite ? Double(v) : 0) }
    public static func s(_ v: String) -> ArcJSON { .string(v) }
    public static func b(_ v: Bool) -> ArcJSON { .bool(v) }
    public static func nums(_ v: [Double]) -> ArcJSON { .array(v.map { ArcJSON.n($0) }) }

    // MARK: — Accessors
    public subscript(key: String) -> ArcJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let d) = self { return d }; return nil }
    public var intValue: Int? {
        if case .number(let d) = self, d.isFinite, abs(d) < 9.0e15 { return Int(d.rounded()) }
        return nil
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [ArcJSON]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: ArcJSON]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    public func str(_ k: String) -> String? { self[k]?.stringValue }
    public func dbl(_ k: String) -> Double? { self[k]?.doubleValue }
    public func flt(_ k: String) -> Float? { self[k]?.doubleValue.map { Float($0) } }
    public func cgf(_ k: String) -> CGFloat? { self[k]?.doubleValue.map { CGFloat($0) } }
    public func integer(_ k: String) -> Int? { self[k]?.intValue }
    public func flag(_ k: String) -> Bool? { self[k]?.boolValue }
    public func list(_ k: String) -> [ArcJSON]? { self[k]?.arrayValue }
    public func dict(_ k: String) -> ArcJSON? {
        if let v = self[k], case .object = v { return v }
        return nil
    }
    /// First present key among aliases (used to accept other producers' spellings).
    public func first(_ keys: [String]) -> ArcJSON? {
        for k in keys { if let v = self[k], !v.isNull { return v } }
        return nil
    }
    public func doubles() -> [Double]? {
        guard case .array(let a) = self else { return nil }
        let d = a.compactMap { $0.doubleValue }
        return d.count == a.count ? d : nil
    }

    /// `settings.global` / `settings.parts` convenience (module settings shape).
    public var global: ArcJSON { self["global"] ?? .object([:]) }
    public var parts: ArcJSON { self["parts"] ?? .object([:]) }

    /// Recursive object merge: keys in `overlay` win; nested objects merge;
    /// arrays and scalars are replaced. Keys only present in `self` survive
    /// (this is how unknown / not-currently-loaded fields are preserved).
    public func merged(with overlay: ArcJSON) -> ArcJSON {
        guard case .object(let base) = self, case .object(let top) = overlay else { return overlay }
        var out = base
        for (k, v) in top {
            if let existing = out[k] { out[k] = existing.merged(with: v) } else { out[k] = v }
        }
        return .object(out)
    }

    // MARK: — Codable bridging
    public static func from<T: Encodable>(_ value: T) -> ArcJSON {
        guard let data = try? JSONEncoder().encode(value),
              let j = try? JSONDecoder().decode(ArcJSON.self, from: data) else { return .null }
        return j
    }
    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Small mutable object builder — keeps big capture() bodies to simple,
/// individually type-checked statements.
public struct ArcJB {
    public var d: [String: ArcJSON] = [:]
    public init() {}
    public mutating func num(_ k: String, _ v: Double) { d[k] = .n(v) }
    public mutating func num(_ k: String, _ v: Float) { d[k] = .n(v) }
    public mutating func num(_ k: String, _ v: Int) { d[k] = .n(v) }
    public mutating func num(_ k: String, _ v: CGFloat) { d[k] = .n(v) }
    public mutating func str(_ k: String, _ v: String) { d[k] = .string(v) }
    public mutating func flag(_ k: String, _ v: Bool) { d[k] = .bool(v) }
    public mutating func set(_ k: String, _ v: ArcJSON) { d[k] = v }
    public mutating func vec(_ k: String, _ v: [Double]) { d[k] = ArcJSON.nums(v) }
    public var json: ArcJSON { .object(d) }
}
