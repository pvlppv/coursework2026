//
//  Theme.swift
//  Sotie
//
//
//  Multi-theme system with custom UITrait-driven dynamic colors.
//
//  Architecture
//  ------------
//  Every theme color is a `UIColor { traitCollection in ... }` provider that
//  resolves both:
//    1. `userInterfaceStyle` — light vs dark
//    2. `SotieThemeVariantTrait`  — the active palette (parchment, ink, sage, ...)
//
//  When `ThemeManager.shared.setVariant(...)` is called, we mutate the
//  variant trait on the active window scene. UIKit + SwiftUI both observe
//  the change and re-resolve every dynamic color in place. No view tree
//  rebuild, no `.id()` reset, no migration of existing call sites.
//
//  This means `Color.theme.backgroundPrimary` keeps working everywhere it's
//  used today, but now reflects the active palette and mode automatically.
//

import Combine
import SwiftUI
import UIKit

// MARK: - Theme Variant
enum ThemeVariant: String, CaseIterable, Identifiable, Sendable, Codable {
  case parchment
  case ink
  case sage
  case dusk
  case iris
  case blush

  var id: String { rawValue }

  /// Localization key for the visible name.
  var titleKey: String {
    switch self {
    case .parchment: return "theme.variant.parchment"
    case .ink: return "theme.variant.ink"
    case .sage: return "theme.variant.sage"
    case .dusk: return "theme.variant.dusk"
    case .iris: return "theme.variant.iris"
    case .blush: return "theme.variant.blush"
    }
  }

  /// SF Symbol used as a quick visual cue in the picker.
  var iconName: String {
    switch self {
    case .parchment: return "book.closed.fill"
    case .ink: return "circle.lefthalf.filled"
    case .sage: return "leaf.fill"
    case .dusk: return "moon.stars.fill"
    case .iris: return "sparkle"
    case .blush: return "heart.fill"
    }
  }

  /// Background color (light mode) for the picker swatch.
  /// Values mirror `Palette.<variant>Light.backgroundPrimary`.
  var previewLightHex: String {
    switch self {
    case .parchment: return "#EEDFC2"
    case .ink: return "#EDEDED"
    case .sage: return "#DDE5D2"
    case .dusk: return "#D4DCE6"
    case .iris: return "#DED7E8"
    case .blush: return "#EDD3CC"
    }
  }

  /// Background color (dark mode) for the picker swatch.
  /// Values mirror `Palette.<variant>Dark.backgroundPrimary`.
  var previewDarkHex: String {
    switch self {
    case .parchment: return "#2A221B"
    case .ink: return "#141414"
    case .sage: return "#1F2520"
    case .dusk: return "#1E2330"
    case .iris: return "#221E2E"
    case .blush: return "#271E1C"
    }
  }

  /// Accent color (light mode) shown as a dot inside the swatch — gives the
  /// palette an identity beyond just the background surface.
  var previewLightAccentHex: String {
    switch self {
    case .parchment: return "#B8743F"
    case .ink: return "#0F0F0F"
    case .sage: return "#4F7A5A"
    case .dusk: return "#3D5A8C"
    case .iris: return "#6A5DA0"
    case .blush: return "#A85A52"
    }
  }

  /// Accent color (dark mode) shown as a dot inside the swatch.
  var previewDarkAccentHex: String {
    switch self {
    case .parchment: return "#D4956B"
    case .ink: return "#F7F7F7"
    case .sage: return "#9CC0A2"
    case .dusk: return "#8FA8D2"
    case .iris: return "#B0A2D9"
    case .blush: return "#DFA39C"
    }
  }
}

// MARK: - Custom UITrait
/// Custom trait that propagates the active `ThemeVariant` through the trait
/// collection. Dynamic `UIColor` providers read this trait to pick the right
/// palette. iOS 17+.
@available(iOS 17.0, *)
struct SotieThemeVariantTrait: UITraitDefinition {
  static let defaultValue: String = ThemeVariant.sage.rawValue
  static let identifier: String = "com.pvlppv.sotie.themeVariant"
  static let affectsColorAppearance: Bool = true
  static let name: String = "Sotie Theme Variant"
}

@available(iOS 17.0, *)
extension UITraitCollection {
  fileprivate var sotieVariant: ThemeVariant {
    let raw = self[SotieThemeVariantTrait.self]
    return ThemeVariant(rawValue: raw) ?? .sage
  }
}

@available(iOS 17.0, *)
extension UIMutableTraits {
  fileprivate mutating func setSotieVariant(_ variant: ThemeVariant) {
    self[SotieThemeVariantTrait.self] = variant.rawValue
  }
}

// MARK: - Theme Manager
/// Single source of truth for the active palette. Mirrors the
/// `LanguageManager` pattern: persisted via `UserDefaults`, exposes
/// `@Published` state for SwiftUI observers, and applies the trait to the
/// active window scene so every dynamic color re-resolves automatically.
@MainActor
final class ThemeManager: ObservableObject {
  static let shared = ThemeManager()
  nonisolated static let storageKey = "AppThemeVariant"

  @Published private(set) var variant: ThemeVariant

  private init() {
    let stored = UserDefaults.standard.string(forKey: Self.storageKey)
    self.variant = stored.flatMap(ThemeVariant.init(rawValue:)) ?? .sage
  }

  /// Apply the persisted variant on launch. Safe to call before any
  /// window scene is connected — the trait push is a no-op then; call
  /// again from a SwiftUI `.onAppear` once the scene exists.
  func applyOnLaunch() {
    Theme.updateGlobalCursorColor()
    applyToWindows()
  }

  /// Apply the variant to any newly connected window. Call from
  /// `ContentView.onAppear` so the trait reaches the window once the
  /// SwiftUI scene is live.
  func applyToConnectedWindows() {
    applyToWindows()
  }

  /// Switch to a new variant. Persists the choice, propagates the trait to
  /// every connected window scene, and refreshes UIKit appearance proxies.
  func setVariant(_ newVariant: ThemeVariant) {
    guard newVariant != variant else { return }
    variant = newVariant
    UserDefaults.standard.set(newVariant.rawValue, forKey: Self.storageKey)
    applyToWindows()
    Theme.updateGlobalCursorColor()
  }

  private func applyToWindows() {
    guard #available(iOS 17.0, *) else { return }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        window.traitOverrides.setSotieVariant(variant)
      }
    }
  }

  /// Resolve the current variant from a trait collection (used inside
  /// dynamic `UIColor` providers). Falls back to the manager's value when
  /// the custom trait isn't present (e.g. during launch before the trait
  /// is set on the window).
  fileprivate static func variant(for traits: UITraitCollection) -> ThemeVariant {
    if #available(iOS 17.0, *) {
      let resolved = traits.sotieVariant
      // When the trait hasn't been set yet (launch, previews) the trait
      // collection returns the default. Cross-check against the manager so
      // first-launch reads honor the user's persisted choice immediately.
      if resolved == .sage {
        return ThemeManager.sharedSnapshot
      }
      return resolved
    }
    return ThemeManager.sharedSnapshot
  }

  /// Thread-safe snapshot of the current variant. Used from non-MainActor
  /// `UIColor` providers, which iOS may call off-main.
  nonisolated static var sharedSnapshot: ThemeVariant {
    let stored = UserDefaults.standard.string(forKey: storageKey)
    return stored.flatMap(ThemeVariant.init(rawValue:)) ?? .sage
  }
}

// MARK: - Theme Environment
struct ThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue = Theme()
}

extension EnvironmentValues {
  var theme: Theme {
    get { self[ThemeEnvironmentKey.self] }
    set { self[ThemeEnvironmentKey.self] = newValue }
  }
}

// MARK: - Theme Structure
struct Theme {
  let colors: ThemeColors

  init() {
    self.colors = ThemeColors()
  }
}

// MARK: - Palette
/// Per-variant, per-mode palette. All values are concrete sRGB tuples.
/// `ThemeColors` resolves the right palette at draw time by inspecting the
/// trait collection, so this struct is just data.
private struct Palette {
  let backgroundPrimary: UIColor
  let backgroundSecondary: UIColor
  let backgroundTertiary: UIColor
  let inputBackground: UIColor

  let textPrimary: UIColor
  let textSecondary: UIColor
  let textTertiary: UIColor

  let accentPrimary: UIColor
  let accentSecondary: UIColor
  let accentTertiary: UIColor

  let divider: UIColor
  let shadow: UIColor
  let success: UIColor
  let warning: UIColor
  let error: UIColor

  let cardBackground: UIColor
  let cardBorder: UIColor

  let buttonBackground: UIColor
  let buttonText: UIColor
  let buttonSecondaryBackground: UIColor
  let buttonSecondaryText: UIColor

  let cursorColor: UIColor
}

/// Resolve a `Palette` for a (variant, isDark) pair. All numeric values
/// live here so re-tuning a theme is a single-file edit.
private func palette(for variant: ThemeVariant, isDark: Bool) -> Palette {
  switch variant {
  case .parchment:
    return isDark ? .parchmentDark : .parchmentLight
  case .ink:
    return isDark ? .inkDark : .inkLight
  case .sage:
    return isDark ? .sageDark : .sageLight
  case .dusk:
    return isDark ? .duskDark : .duskLight
  case .iris:
    return isDark ? .irisDark : .irisLight
  case .blush:
    return isDark ? .blushDark : .blushLight
  }
}

// MARK: - Theme Colors
/// Dynamic-color facade. Every property is a `Color` wrapping a
/// `UIColor { trait in ... }` provider that resolves the active palette at
/// draw time. Construct once, reuse forever — `Color.theme` is a static.
struct ThemeColors {
  // Background Colors
  let backgroundPrimary: Color
  let backgroundSecondary: Color
  let backgroundTertiary: Color

  // Input/Inset Colors — for elements inset within cards (text fields, pills)
  let inputBackground: Color

  // Text Colors
  let textPrimary: Color
  let textSecondary: Color
  let textTertiary: Color

  // Accent Colors
  let accentPrimary: Color
  let accentSecondary: Color
  let accentTertiary: Color

  // System Colors
  let divider: Color
  let shadow: Color
  let success: Color
  let warning: Color
  let error: Color

  // Card Colors
  let cardBackground: Color
  let cardBorder: Color

  // Button Colors
  let buttonBackground: Color
  let buttonText: Color
  let buttonSecondaryBackground: Color
  let buttonSecondaryText: Color

  // Cursor Colors
  let cursorColor: Color

  init() {
    self.backgroundPrimary = ThemeColors.dynamic { $0.backgroundPrimary }
    self.backgroundSecondary = ThemeColors.dynamic { $0.backgroundSecondary }
    self.backgroundTertiary = ThemeColors.dynamic { $0.backgroundTertiary }
    self.inputBackground = ThemeColors.dynamic { $0.inputBackground }

    self.textPrimary = ThemeColors.dynamic { $0.textPrimary }
    self.textSecondary = ThemeColors.dynamic { $0.textSecondary }
    self.textTertiary = ThemeColors.dynamic { $0.textTertiary }

    self.accentPrimary = ThemeColors.dynamic { $0.accentPrimary }
    self.accentSecondary = ThemeColors.dynamic { $0.accentSecondary }
    self.accentTertiary = ThemeColors.dynamic { $0.accentTertiary }

    self.divider = ThemeColors.dynamic { $0.divider }
    self.shadow = ThemeColors.dynamic { $0.shadow }
    self.success = ThemeColors.dynamic { $0.success }
    self.warning = ThemeColors.dynamic { $0.warning }
    self.error = ThemeColors.dynamic { $0.error }

    self.cardBackground = ThemeColors.dynamic { $0.cardBackground }
    self.cardBorder = ThemeColors.dynamic { $0.cardBorder }

    self.buttonBackground = ThemeColors.dynamic { $0.buttonBackground }
    self.buttonText = ThemeColors.dynamic { $0.buttonText }
    self.buttonSecondaryBackground = ThemeColors.dynamic { $0.buttonSecondaryBackground }
    self.buttonSecondaryText = ThemeColors.dynamic { $0.buttonSecondaryText }

    self.cursorColor = ThemeColors.dynamic { $0.cursorColor }
  }

  /// Build a `Color` whose underlying `UIColor` re-resolves on every draw,
  /// using the trait collection to pick the right (variant, mode) palette.
  private static func dynamic(_ pick: @escaping (Palette) -> UIColor) -> Color {
    Color(
      UIColor { traits in
        let variant = ThemeManager.variant(for: traits)
        let isDark = traits.userInterfaceStyle == .dark
        return pick(palette(for: variant, isDark: isDark))
      }
    )
  }
}

// MARK: - Color Extensions for Easy Access
extension Color {
  static let theme = ThemeColors()

  // Computed properties to avoid static-let initialization deadlock.
  // Static lets use a dispatch_once lock; accessing Color.theme (also a
  // static let) inside that lock causes a re-entrant deadlock/crash.
  static var themeButtonBackground: Color { Color.theme.buttonBackground }
  static var themeCardBackground: Color { Color.theme.cardBackground }
  static var themeBackgroundPrimary: Color { Color.theme.backgroundPrimary }
  static var themeButtonText: Color { Color.theme.buttonText }
  static var themeTextSecondary: Color { Color.theme.textSecondary }
  static var themeTextPrimary: Color { Color.theme.textPrimary }
}

// MARK: - Theme Modifiers
extension View {
  func themeBackground(_ level: BackgroundLevel = .primary) -> some View {
    switch level {
    case .primary:
      return self.background(Color.theme.backgroundPrimary)
    case .secondary:
      return self.background(Color.theme.backgroundSecondary)
    case .tertiary:
      return self.background(Color.theme.backgroundTertiary)
    case .card:
      return self.background(Color.theme.cardBackground)
    }
  }

  func themeText(_ level: TextLevel = .primary) -> some View {
    switch level {
    case .primary:
      return self.foregroundColor(Color.theme.textPrimary)
    case .secondary:
      return self.foregroundColor(Color.theme.textSecondary)
    case .tertiary:
      return self.foregroundColor(Color.theme.textTertiary)
    case .accent:
      return self.foregroundColor(Color.theme.accentPrimary)
    }
  }

  // Unified Shadow System - creates breathing room and depth hierarchy
  func themeShadow(_ level: ShadowLevel = .medium) -> some View {
    Group {
      switch level {
      case .subtle:
        // For subtle elements like search bars, filter buttons
        self
          .shadow(color: Color.theme.shadow.opacity(0.04), radius: 2, x: 0, y: 1)
          .shadow(color: Color.theme.shadow.opacity(0.02), radius: 1, x: 0, y: 0.5)
      case .small:
        // For small interactive elements like category chips when selected
        self
          .shadow(color: Color.theme.shadow.opacity(0.08), radius: 4, x: 0, y: 2)
          .shadow(color: Color.theme.shadow.opacity(0.04), radius: 2, x: 0, y: 1)
      case .medium:
        // For cards: trackers, summary metrics - main content
        self
          .shadow(color: Color.theme.shadow.opacity(0.12), radius: 8, x: 0, y: 4)
          .shadow(color: Color.theme.shadow.opacity(0.06), radius: 3, x: 0, y: 2)
      case .large:
        // For prominent elements: insight card, FAB
        self
          .shadow(color: Color.theme.shadow.opacity(0.16), radius: 12, x: 0, y: 6)
          .shadow(color: Color.theme.shadow.opacity(0.08), radius: 4, x: 0, y: 2)
      case .elevated:
        // For floating elements: FAB, modals
        self
          .shadow(color: Color.theme.shadow.opacity(0.20), radius: 16, x: 0, y: 8)
          .shadow(color: Color.theme.shadow.opacity(0.12), radius: 6, x: 0, y: 3)
      }
    }
  }

  func themeCard() -> some View {
    self
      .themeBackground(.card)
      .cornerRadius(Spacing.cornerRadiusMedium)
      .themeShadow(.medium)
  }

  func themeButton() -> some View {
    self
      .background(Color.theme.buttonBackground)
      .foregroundColor(Color.theme.buttonText)
      .cornerRadius(Spacing.cornerRadiusMedium)
      .themeShadow(.medium)
  }

  func themeButtonSecondary() -> some View {
    self
      .background(Color.theme.buttonSecondaryBackground)
      .foregroundColor(Color.theme.buttonSecondaryText)
      .cornerRadius(Spacing.cornerRadiusMedium)
      .themeShadow(.small)
  }

  func themeCursor() -> some View {
    self.accentColor(Color.theme.cursorColor)
  }
}

// MARK: - Global Cursor Color Setup
extension Theme {
  /// Sets up global cursor color for all text fields.
  /// Call this once in your app initialization, and again whenever the
  /// theme variant changes (`ThemeManager.setVariant` does this for you).
  static func setupGlobalCursorColor() {
    let dynamicCursor = UIColor { traits in
      let variant = ThemeManager.variant(for: traits)
      let isDark = traits.userInterfaceStyle == .dark
      return palette(for: variant, isDark: isDark).cursorColor
    }
    UITextField.appearance().tintColor = dynamicCursor
    UITextView.appearance().tintColor = dynamicCursor
    UISearchBar.appearance().tintColor = dynamicCursor
  }

  /// Updates global cursor color when theme changes.
  static func updateGlobalCursorColor() {
    setupGlobalCursorColor()
  }
}

// MARK: - Theme Enums
enum BackgroundLevel {
  case primary, secondary, tertiary, card
}

enum TextLevel {
  case primary, secondary, tertiary, accent
}

enum ShadowLevel {
  case subtle  // Search bars, filters
  case small  // Selected chips, small buttons
  case medium  // Tracker cards, metric cards
  case large  // Insight card, prominent cards
  case elevated  // FAB, floating elements
}

// MARK: - Hex helper
private extension UIColor {
  /// Convenience initializer for sRGB hex colors used in the palette
  /// definitions below. Keeps each palette readable as a flat list of hex
  /// values rather than `UIColor(red:green:blue:alpha:)` boilerplate.
  convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b, alpha: alpha)
  }
}

// MARK: - Palettes
//
// Each palette is hand-tuned for both modes:
//   • Light mode targets WCAG AA on body text (≥ 4.5:1 contrast).
//   • Dark mode keeps the hue identity of the theme without going muddy.
//   • Shadows are uniformly black with mode-appropriate alpha.
//   • Buttons use the theme's strongest hue for press affordance.
//
// Order: parchment (default) → ink → sage → dusk → iris → blush.

// MARK: Parchment — warm beige paper (default)
private extension Palette {
  static let parchmentLight = Palette(
    backgroundPrimary:    UIColor(hex: 0xEEDFC2),
    backgroundSecondary:  UIColor(hex: 0xFAF1DA),
    backgroundTertiary:   UIColor(hex: 0xE5D3B1),
    inputBackground:      UIColor(hex: 0xE9D9BB),
    textPrimary:          UIColor(hex: 0x2A1F12),
    textSecondary:        UIColor(hex: 0x6B5640),
    textTertiary:         UIColor(hex: 0x9A856A),
    accentPrimary:        UIColor(hex: 0xB8743F),
    accentSecondary:      UIColor(hex: 0xCC8E5C),
    accentTertiary:       UIColor(hex: 0xDDAD83),
    divider:              UIColor(hex: 0xDCC9A4),
    shadow:               UIColor(red: 0.20, green: 0.13, blue: 0.05, alpha: 0.12),
    success:              UIColor(hex: 0x6B8770),
    warning:              UIColor(hex: 0xC1853B),
    error:                UIColor(hex: 0xA84A3A),
    cardBackground:       UIColor(hex: 0xFAF1DA),
    cardBorder:           UIColor(hex: 0xE3CFA8),
    buttonBackground:     UIColor(hex: 0x2A1F12),
    buttonText:           UIColor(hex: 0xFAF1DA),
    buttonSecondaryBackground: UIColor(hex: 0xE3CFA8),
    buttonSecondaryText:  UIColor(hex: 0x2A1F12),
    cursorColor:          UIColor(hex: 0xB8743F)
  )

  static let parchmentDark = Palette(
    backgroundPrimary:    UIColor(hex: 0x2A221B),
    backgroundSecondary:  UIColor(hex: 0x362B22),
    backgroundTertiary:   UIColor(hex: 0x40342A),
    inputBackground:      UIColor(hex: 0x40342A),
    textPrimary:          UIColor(hex: 0xF2E7D2),
    textSecondary:        UIColor(hex: 0xC4B493),
    textTertiary:         UIColor(hex: 0x9A8970),
    accentPrimary:        UIColor(hex: 0xD4956B),
    accentSecondary:      UIColor(hex: 0xB87B52),
    accentTertiary:       UIColor(hex: 0x8C5C3B),
    divider:              UIColor(hex: 0x4A3D2D),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45),
    success:              UIColor(hex: 0x9CB39F),
    warning:              UIColor(hex: 0xD4A467),
    error:                UIColor(hex: 0xC97365),
    cardBackground:       UIColor(hex: 0x362B22),
    cardBorder:           UIColor(hex: 0x4A3D2D),
    buttonBackground:     UIColor(hex: 0xF2E7D2),
    buttonText:           UIColor(hex: 0x2A221B),
    buttonSecondaryBackground: UIColor(hex: 0x4A3D2D),
    buttonSecondaryText:  UIColor(hex: 0xE8D9BB),
    cursorColor:          UIColor(hex: 0xD4956B)
  )
}

// MARK: Ink — strict B&W (current monochrome theme, preserved)
private extension Palette {
  static let inkLight = Palette(
    backgroundPrimary:    UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1.0),
    backgroundSecondary:  UIColor.white,
    backgroundTertiary:   UIColor(red: 0.89, green: 0.89, blue: 0.89, alpha: 1.0),
    inputBackground:      UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0),
    textPrimary:          UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.0),
    textSecondary:        UIColor(red: 0.36, green: 0.36, blue: 0.36, alpha: 1.0),
    textTertiary:         UIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1.0),
    accentPrimary:        UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1.0),
    accentSecondary:      UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1.0),
    accentTertiary:       UIColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1.0),
    divider:              UIColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.10),
    success:              UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1.0),
    warning:              UIColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0),
    error:                UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0),
    cardBackground:       UIColor.white,
    cardBorder:           UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1.0),
    buttonBackground:     UIColor.black,
    buttonText:           UIColor.white,
    buttonSecondaryBackground: UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0),
    buttonSecondaryText:  UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0),
    cursorColor:          UIColor.black
  )

  static let inkDark = Palette(
    backgroundPrimary:    UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0),
    backgroundSecondary:  UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
    backgroundTertiary:   UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0),
    inputBackground:      UIColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1.0),
    textPrimary:          UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0),
    textSecondary:        UIColor(red: 0.68, green: 0.68, blue: 0.68, alpha: 1.0),
    textTertiary:         UIColor(red: 0.48, green: 0.48, blue: 0.48, alpha: 1.0),
    accentPrimary:        UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0),
    accentSecondary:      UIColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0),
    accentTertiary:       UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1.0),
    divider:              UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1.0),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45),
    success:              UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1.0),
    warning:              UIColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1.0),
    error:                UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1.0),
    cardBackground:       UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0),
    cardBorder:           UIColor(red: 0.26, green: 0.26, blue: 0.26, alpha: 1.0),
    buttonBackground:     UIColor.white,
    buttonText:           UIColor.black,
    buttonSecondaryBackground: UIColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1.0),
    buttonSecondaryText:  UIColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0),
    cursorColor:          UIColor.white
  )
}

// MARK: Sage — soft eucalyptus / forest dusk
private extension Palette {
  static let sageLight = Palette(
    backgroundPrimary:    UIColor(hex: 0xDDE5D2),
    backgroundSecondary:  UIColor(hex: 0xEEF2E4),
    backgroundTertiary:   UIColor(hex: 0xCFDAC2),
    inputBackground:      UIColor(hex: 0xD5E0C8),
    textPrimary:          UIColor(hex: 0x1A2218),
    textSecondary:        UIColor(hex: 0x435041),
    textTertiary:         UIColor(hex: 0x738075),
    accentPrimary:        UIColor(hex: 0x4F7A5A),
    accentSecondary:      UIColor(hex: 0x6B937A),
    accentTertiary:       UIColor(hex: 0x95B49E),
    divider:              UIColor(hex: 0xC4D0BA),
    shadow:               UIColor(red: 0.05, green: 0.13, blue: 0.07, alpha: 0.12),
    success:              UIColor(hex: 0x4F7A5A),
    warning:              UIColor(hex: 0xB59149),
    error:                UIColor(hex: 0xA85A50),
    cardBackground:       UIColor(hex: 0xEEF2E4),
    cardBorder:           UIColor(hex: 0xC9D6BD),
    buttonBackground:     UIColor(hex: 0x1A2218),
    buttonText:           UIColor(hex: 0xEEF2E4),
    buttonSecondaryBackground: UIColor(hex: 0xC9D6BD),
    buttonSecondaryText:  UIColor(hex: 0x1A2218),
    cursorColor:          UIColor(hex: 0x4F7A5A)
  )

  static let sageDark = Palette(
    backgroundPrimary:    UIColor(hex: 0x1F2520),
    backgroundSecondary:  UIColor(hex: 0x2C342D),
    backgroundTertiary:   UIColor(hex: 0x363F37),
    inputBackground:      UIColor(hex: 0x363F37),
    textPrimary:          UIColor(hex: 0xE3EBDC),
    textSecondary:        UIColor(hex: 0xACBAAE),
    textTertiary:         UIColor(hex: 0x7E8E80),
    accentPrimary:        UIColor(hex: 0x9CC0A2),
    accentSecondary:      UIColor(hex: 0x7DA188),
    accentTertiary:       UIColor(hex: 0x5E8268),
    divider:              UIColor(hex: 0x40493F),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45),
    success:              UIColor(hex: 0x9CC0A2),
    warning:              UIColor(hex: 0xC8A467),
    error:                UIColor(hex: 0xC97365),
    cardBackground:       UIColor(hex: 0x2C342D),
    cardBorder:           UIColor(hex: 0x40493F),
    buttonBackground:     UIColor(hex: 0xE3EBDC),
    buttonText:           UIColor(hex: 0x1F2520),
    buttonSecondaryBackground: UIColor(hex: 0x40493F),
    buttonSecondaryText:  UIColor(hex: 0xCFD9C7),
    cursorColor:          UIColor(hex: 0x9CC0A2)
  )
}

// MARK: Dusk — desaturated slate / deep navy
private extension Palette {
  static let duskLight = Palette(
    backgroundPrimary:    UIColor(hex: 0xD4DCE6),
    backgroundSecondary:  UIColor(hex: 0xEAEFF5),
    backgroundTertiary:   UIColor(hex: 0xC5D0DD),
    inputBackground:      UIColor(hex: 0xCDD7E2),
    textPrimary:          UIColor(hex: 0x141A24),
    textSecondary:        UIColor(hex: 0x3D4858),
    textTertiary:         UIColor(hex: 0x6E7888),
    accentPrimary:        UIColor(hex: 0x3D5A8C),
    accentSecondary:      UIColor(hex: 0x6079A8),
    accentTertiary:       UIColor(hex: 0x95A8C5),
    divider:              UIColor(hex: 0xBCC6D3),
    shadow:               UIColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 0.12),
    success:              UIColor(hex: 0x4F7A5A),
    warning:              UIColor(hex: 0xC1853B),
    error:                UIColor(hex: 0xA84A3A),
    cardBackground:       UIColor(hex: 0xEAEFF5),
    cardBorder:           UIColor(hex: 0xC1CCDA),
    buttonBackground:     UIColor(hex: 0x141A24),
    buttonText:           UIColor(hex: 0xEAEFF5),
    buttonSecondaryBackground: UIColor(hex: 0xC1CCDA),
    buttonSecondaryText:  UIColor(hex: 0x141A24),
    cursorColor:          UIColor(hex: 0x3D5A8C)
  )

  static let duskDark = Palette(
    backgroundPrimary:    UIColor(hex: 0x1E2330),
    backgroundSecondary:  UIColor(hex: 0x2A3144),
    backgroundTertiary:   UIColor(hex: 0x343C52),
    inputBackground:      UIColor(hex: 0x343C52),
    textPrimary:          UIColor(hex: 0xDEE4EE),
    textSecondary:        UIColor(hex: 0xA6B2C5),
    textTertiary:         UIColor(hex: 0x7782A0),
    accentPrimary:        UIColor(hex: 0x8FA8D2),
    accentSecondary:      UIColor(hex: 0x7090BC),
    accentTertiary:       UIColor(hex: 0x52739E),
    divider:              UIColor(hex: 0x3D4660),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45),
    success:              UIColor(hex: 0x9CC0A2),
    warning:              UIColor(hex: 0xD4A467),
    error:                UIColor(hex: 0xC97365),
    cardBackground:       UIColor(hex: 0x2A3144),
    cardBorder:           UIColor(hex: 0x3D4660),
    buttonBackground:     UIColor(hex: 0xDEE4EE),
    buttonText:           UIColor(hex: 0x1E2330),
    buttonSecondaryBackground: UIColor(hex: 0x3D4660),
    buttonSecondaryText:  UIColor(hex: 0xC8D1E1),
    cursorColor:          UIColor(hex: 0x8FA8D2)
  )
}

// MARK: Iris — desaturated lavender / aubergine
private extension Palette {
  static let irisLight = Palette(
    backgroundPrimary:    UIColor(hex: 0xDED7E8),
    backgroundSecondary:  UIColor(hex: 0xEDE8F4),
    backgroundTertiary:   UIColor(hex: 0xCEC5DD),
    inputBackground:      UIColor(hex: 0xD7CFE4),
    textPrimary:          UIColor(hex: 0x1A1626),
    textSecondary:        UIColor(hex: 0x443E55),
    textTertiary:         UIColor(hex: 0x756D86),
    accentPrimary:        UIColor(hex: 0x6A5DA0),
    accentSecondary:      UIColor(hex: 0x8B7EB7),
    accentTertiary:       UIColor(hex: 0xACA1CC),
    divider:              UIColor(hex: 0xC4BAD6),
    shadow:               UIColor(red: 0.10, green: 0.07, blue: 0.18, alpha: 0.12),
    success:              UIColor(hex: 0x4F7A5A),
    warning:              UIColor(hex: 0xC1853B),
    error:                UIColor(hex: 0xA84A3A),
    cardBackground:       UIColor(hex: 0xEDE8F4),
    cardBorder:           UIColor(hex: 0xCAC0DC),
    buttonBackground:     UIColor(hex: 0x1A1626),
    buttonText:           UIColor(hex: 0xEDE8F4),
    buttonSecondaryBackground: UIColor(hex: 0xCAC0DC),
    buttonSecondaryText:  UIColor(hex: 0x1A1626),
    cursorColor:          UIColor(hex: 0x6A5DA0)
  )

  static let irisDark = Palette(
    backgroundPrimary:    UIColor(hex: 0x221E2E),
    backgroundSecondary:  UIColor(hex: 0x2E2942),
    backgroundTertiary:   UIColor(hex: 0x393352),
    inputBackground:      UIColor(hex: 0x393352),
    textPrimary:          UIColor(hex: 0xE0DAEC),
    textSecondary:        UIColor(hex: 0xAFA6C2),
    textTertiary:         UIColor(hex: 0x7E7799),
    accentPrimary:        UIColor(hex: 0xB0A2D9),
    accentSecondary:      UIColor(hex: 0x9286BD),
    accentTertiary:       UIColor(hex: 0x73679E),
    divider:              UIColor(hex: 0x423B5C),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45),
    success:              UIColor(hex: 0x9CC0A2),
    warning:              UIColor(hex: 0xD4A467),
    error:                UIColor(hex: 0xC97365),
    cardBackground:       UIColor(hex: 0x2E2942),
    cardBorder:           UIColor(hex: 0x423B5C),
    buttonBackground:     UIColor(hex: 0xE0DAEC),
    buttonText:           UIColor(hex: 0x221E2E),
    buttonSecondaryBackground: UIColor(hex: 0x423B5C),
    buttonSecondaryText:  UIColor(hex: 0xCBC2DE),
    cursorColor:          UIColor(hex: 0xB0A2D9)
  )
}

// MARK: Blush — dusty rose / cocoa-rose
private extension Palette {
  static let blushLight = Palette(
    backgroundPrimary:    UIColor(hex: 0xEDD3CC),
    backgroundSecondary:  UIColor(hex: 0xF8E2DC),
    backgroundTertiary:   UIColor(hex: 0xE0BFB7),
    inputBackground:      UIColor(hex: 0xE6C7BF),
    textPrimary:          UIColor(hex: 0x261814),
    textSecondary:        UIColor(hex: 0x584440),
    textTertiary:         UIColor(hex: 0x8A746F),
    accentPrimary:        UIColor(hex: 0xA85A52),
    accentSecondary:      UIColor(hex: 0xC2786E),
    accentTertiary:       UIColor(hex: 0xD49D94),
    divider:              UIColor(hex: 0xD8B6AD),
    shadow:               UIColor(red: 0.20, green: 0.08, blue: 0.06, alpha: 0.12),
    success:              UIColor(hex: 0x4F7A5A),
    warning:              UIColor(hex: 0xC1853B),
    error:                UIColor(hex: 0xA84A3A),
    cardBackground:       UIColor(hex: 0xF8E2DC),
    cardBorder:           UIColor(hex: 0xDDB9B0),
    buttonBackground:     UIColor(hex: 0x261814),
    buttonText:           UIColor(hex: 0xF8E2DC),
    buttonSecondaryBackground: UIColor(hex: 0xDDB9B0),
    buttonSecondaryText:  UIColor(hex: 0x261814),
    cursorColor:          UIColor(hex: 0xA85A52)
  )

  static let blushDark = Palette(
    backgroundPrimary:    UIColor(hex: 0x271E1C),
    backgroundSecondary:  UIColor(hex: 0x342726),
    backgroundTertiary:   UIColor(hex: 0x3F2F2D),
    inputBackground:      UIColor(hex: 0x3F2F2D),
    textPrimary:          UIColor(hex: 0xEFE0DB),
    textSecondary:        UIColor(hex: 0xC4ABA7),
    textTertiary:         UIColor(hex: 0x8E7A77),
    accentPrimary:        UIColor(hex: 0xDFA39C),
    accentSecondary:      UIColor(hex: 0xC0857E),
    accentTertiary:       UIColor(hex: 0x956962),
    divider:              UIColor(hex: 0x4A3936),
    shadow:               UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45),
    success:              UIColor(hex: 0x9CC0A2),
    warning:              UIColor(hex: 0xD4A467),
    error:                UIColor(hex: 0xC97365),
    cardBackground:       UIColor(hex: 0x342726),
    cardBorder:           UIColor(hex: 0x4A3936),
    buttonBackground:     UIColor(hex: 0xEFE0DB),
    buttonText:           UIColor(hex: 0x271E1C),
    buttonSecondaryBackground: UIColor(hex: 0x4A3936),
    buttonSecondaryText:  UIColor(hex: 0xDDC4BD),
    cursorColor:          UIColor(hex: 0xDFA39C)
  )
}
