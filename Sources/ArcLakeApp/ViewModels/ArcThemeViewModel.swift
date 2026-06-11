
import SwiftUI

@MainActor
public final class ArcThemeViewModel: ObservableObject {
    public enum Theme: String, CaseIterable {
        case stealth, night, day, departure, ashTree, neon, solar, arctic, molten, quantum

        var background: Color {
            switch self {
            case .stealth:   return Color(hex: "#060a10")
            case .night:     return Color(hex: "#020a14")
            case .day:       return Color(hex: "#0a1628")
            case .departure: return Color(hex: "#0d0a1a")
            case .ashTree:   return Color(hex: "#0a140a")
            case .neon:      return Color(hex: "#080010")
            case .solar:     return Color(hex: "#140a00")
            case .arctic:    return Color(hex: "#001428")
            case .molten:    return Color(hex: "#140500")
            case .quantum:   return Color(hex: "#050014")
            }
        }

        var accent: Color {
            switch self {
            case .stealth:   return Color(hex: "#00e5ff")
            case .night:     return Color(hex: "#00d4ff")
            case .day:       return Color(hex: "#0088ff")
            case .departure: return Color(hex: "#aa44ff")
            case .ashTree:   return Color(hex: "#44ff88")
            case .neon:      return Color(hex: "#ff00ff")
            case .solar:     return Color(hex: "#ffaa00")
            case .arctic:    return Color(hex: "#88ddff")
            case .molten:    return Color(hex: "#ff4400")
            case .quantum:   return Color(hex: "#8800ff")
            }
        }
    }

    @Published public var current: Theme = Theme(
        rawValue: UserDefaults.standard.string(forKey: "arcLakeTheme") ?? ""
    ) ?? .stealth {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "arcLakeTheme") }
    }

    public var bg: Color     { current.background }
    public var accent: Color { current.accent }

    public func cycle() {
        let all = Theme.allCases
        let idx = ((all.firstIndex(of: current) ?? 0) + 1) % all.count
        current = all[idx]
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

