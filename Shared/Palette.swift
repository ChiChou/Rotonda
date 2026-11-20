import SwiftUI
import UIKit

/// Colours come from Italian road signs: the blue of the Rotonda icon for structure and
/// actions, green/red for VERO/FALSO, and warning-sign amber for numbers and key facts.
extension Color {
    static let signBlue = Color(light: 0x0B67C9, dark: 0x4C9DFF)
    static let signBlueDeep = Color(light: 0x3E55AE, dark: 0x6F86E0)
    static let vero = Color(light: 0x1B8A4B, dark: 0x3CCB7F)
    static let falso = Color(light: 0xCC3329, dark: 0xFF6B5E)
    static let amber = Color(light: 0xF2B300, dark: 0xFFC933)
    static let amberInk = Color(light: 0x7A5600, dark: 0xFFD666)
    static let screen = Color(UIColor.systemGroupedBackground)
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let hairline = Color(UIColor.separator)

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension ShapeStyle where Self == LinearGradient {
    static var signGradient: LinearGradient {
        LinearGradient(colors: [Color(light: 0x075DA8, dark: 0x075DA8), Color(light: 0x0B67C9, dark: 0x0B67C9), Color(light: 0x3E55AE, dark: 0x3E55AE)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
