import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private enum PlatformColors {
    #if canImport(UIKit)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceAlt = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator)
    static let borderDark = Color(uiColor: .opaqueSeparator)
    static let text = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    #elseif canImport(AppKit)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceAlt = Color(nsColor: .underPageBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let borderDark = Color(nsColor: .gridColor)
    static let text = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    #endif
}

enum ColorAsset {
    case primary, primaryDark, primaryLight, secondary, accent, success, warning
    case error, background, surface, surfaceAlt, border, borderDark
    case text, textSecondary, textTertiary, textInverse

    var rawValue: String {
        switch self {
        case .primary: "#3B82F6"
        case .primaryDark: "#2563EB"
        case .primaryLight: "#DBEAFE"
        case .secondary: "#06B6D4"
        case .accent, .warning: "#F59E0B"
        case .success: "#10B981"
        case .error: "#EF4444"
        case .background: "#F8FAFC"
        case .surface, .textInverse: "#FFFFFF"
        case .surfaceAlt: "#F1F5F9"
        case .border: "#E2E8F0"
        case .borderDark: "#CBD5E1"
        case .text: "#0F172A"
        case .textSecondary: "#64748B"
        case .textTertiary: "#94A3B8"
        }
    }

    var color: Color {
        switch self {
        case .background:
            return PlatformColors.background
        case .surface:
            return PlatformColors.surface
        case .surfaceAlt:
            return PlatformColors.surfaceAlt
        case .border:
            return PlatformColors.border
        case .borderDark:
            return PlatformColors.borderDark
        case .text:
            return PlatformColors.text
        case .textSecondary:
            return PlatformColors.textSecondary
        case .textTertiary:
            return PlatformColors.textTertiary
        case .primaryLight:
            return ColorAsset.primary.color.opacity(0.18)
        default:
            return Color(hex: rawValue)
        }
    }

}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum AppTheme {
    static let spacing: CGFloat = 8
    static let spacingXs: CGFloat = 4
    static let spacingSm: CGFloat = 8
    static let spacingMd: CGFloat = 12
    static let spacingLg: CGFloat = 16
    static let spacingXl: CGFloat = 20
    static let spacingXxl: CGFloat = 24
    static let spacingXxxl: CGFloat = 32

    static let cornerSm: CGFloat = 8
    static let cornerMd: CGFloat = 12
    static let cornerLg: CGFloat = 16
    static let cornerXl: CGFloat = 20
    static let cornerXxl: CGFloat = 24

    static let roomIcons = [
        "🍽️", "🚿", "🛋️", "🛏️", "💻", "🚗", "🌿", "🧺", "🚪", "🪟",
        "🛁", "🧽", "📦", "🐶", "👕", "📚", "🎮", "🍳", "🪴", "🔧"
    ]

    static let roomColors = [
        "#F59E0B", "#06B6D4", "#8B5CF6", "#EC4899", "#6366F1",
        "#10B981", "#EF4444", "#14B8A6", "#F97316", "#3B82F6"
    ]

    static let frequencies: [(label: String, value: Int)] = [
        ("Every day", 1),
        ("Every 2 days", 2),
        ("Every 3 days", 3),
        ("Twice a week", 4),
        ("Weekly", 7),
        ("Biweekly", 14),
        ("Monthly", 30)
    ]
}
