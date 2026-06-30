//
//  Theme.swift
//  SpottersaurusKit
//
//  Centralized design tokens, ported from the Tailwind brief to native.
//  Platform-neutral scalar tokens (spacing, corner radii, the brand color
//  palette as RGB) live unguarded so they compile on macOS for tests; the
//  SwiftUI `Color` accessors are gated behind `#if canImport(SwiftUI)`.
//

import Foundation

/// Design tokens for Spottersaurus. Both app targets and the Watch read
/// from here so the design system is written once.
public enum Theme {

    // MARK: Spacing scale (points)

    /// 8-pt based spacing scale used across both platforms.
    public enum Spacing {
        public static let xs: Double = 4
        public static let sm: Double = 8
        public static let md: Double = 16
        public static let lg: Double = 24
        public static let xl: Double = 32
    }

    // MARK: Corner radii (points)

    /// `.continuous` squircle radii ported from `rounded-3xl` / `rounded-[40px]`.
    public enum Radius {
        public static let card: Double = 24
        public static let sheet: Double = 40
    }

    // MARK: Brand palette (sRGB components, 0...1)

    /// Raw sRGB color components so the palette is testable without SwiftUI.
    public struct RGBA: Sendable, Equatable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Build from an 8-bit-per-channel hex literal, e.g. `0x33A853`.
        public init(hex: UInt32, alpha: Double = 1) {
            self.red = Double((hex >> 16) & 0xFF) / 255
            self.green = Double((hex >> 8) & 0xFF) / 255
            self.blue = Double(hex & 0xFF) / 255
            self.alpha = alpha
        }
    }

    /// Semantic state palette ported from emerald / amber / rose accents.
    public enum Palette {
        /// OLED black canvas (dark-first).
        public static let canvas = RGBA(hex: 0x000000)
        /// "Optimal" rep state — emerald.
        public static let optimal = RGBA(hex: 0x33A853)
        /// "Caution" / grinding state — amber.
        public static let caution = RGBA(hex: 0xFF9800)
        /// "Alert" / RACK IT state — coral red.
        public static let alert = RGBA(hex: 0xFF3B30)
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension Theme.RGBA {
    /// SwiftUI `Color` for this token.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

public extension Theme {
    /// SwiftUI color accessors for the brand palette.
    enum Colors {
        public static var canvas: Color { Palette.canvas.color }
        public static var optimal: Color { Palette.optimal.color }
        public static var caution: Color { Palette.caution.color }
        public static var alert: Color { Palette.alert.color }
    }
}
#endif
