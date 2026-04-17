//
//  ThemeSettingsView.swift
//  Sotie
//
//
//  Theme picker. Shows every available `ThemeVariant` with a side-by-side
//  light/dark swatch and a checkmark for the active choice. Changing the
//  selection applies the new palette immediately to the entire app via
//  `ThemeManager.setVariant` (which re-pushes the variant trait onto the
//  active window so all dynamic colors re-resolve in place).
//

import SwiftUI

@MainActor
struct ThemeSettingsView: View {
  @EnvironmentObject private var themeManager: ThemeManager

  // Stable, opinionated order. Default (sage) first, then the calm
  // neutrals, then the other colored variants from cool → warm.
  private let orderedVariants: [ThemeVariant] = [
    .sage, .parchment, .ink, .dusk, .iris, .blush,
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.large) {
        VStack(spacing: 0) {
          ForEach(Array(orderedVariants.enumerated()), id: \.element) { index, variant in
            themeRow(for: variant)

            if index < orderedVariants.count - 1 {
              Divider()
                .background(Color.theme.divider)
                .padding(.horizontal, Spacing.medium)
            }
          }
        }
        .background(
          RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
            .fill(Color.theme.backgroundSecondary)
            .themeShadow(.medium)
        )
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.large)
    }
    .themeBackground(.primary)
    .navigationTitle(appLocalizedString(Localizable.themeSettingsTitle))
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Row
  private func themeRow(for variant: ThemeVariant) -> some View {
    let isSelected = themeManager.variant == variant

    return Button {
      guard !isSelected else { return }
      HapticManager.shared.light()
      themeManager.setVariant(variant)
      Analytics.themeChanged(to: variant.rawValue)
    } label: {
      HStack(spacing: Spacing.medium) {
        // Light/dark swatch — communicates that the theme adapts to mode
        // automatically without requiring a separate light/dark toggle.
        ThemeSwatch(variant: variant)

        VStack(alignment: .leading, spacing: 2) {
          Text(appLocalizedString(variant.titleKey))
            .typography(.body)
            .themeText(.primary)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.body)
            .fontWeight(.semibold)
            .themeText(.primary)
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.medium)
      .contentShape(Rectangle())
    }
    .buttonStyle(PlainButtonStyle())
  }
}

// MARK: - Swatch
/// Two side-by-side halves showing the theme's light + dark surface, each
/// carrying a small dot in that mode's accent color. The split + the
/// accent dots together communicate three things at a glance:
///   1. The theme adapts automatically to system mode.
///   2. The hue identity (parchment vs sage vs dusk vs ...).
///   3. The strongest action color you'll see in the app.
private struct ThemeSwatch: View {
  let variant: ThemeVariant

  private let size: CGFloat = 52
  private let dotSize: CGFloat = 10

  var body: some View {
    HStack(spacing: 0) {
      half(
        background: variant.previewLightHex,
        accent: variant.previewLightAccentHex
      )
      half(
        background: variant.previewDarkHex,
        accent: variant.previewDarkAccentHex
      )
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(
      Circle()
        .strokeBorder(Color.theme.cardBorder, lineWidth: 1)
    )
  }

  private func half(background: String, accent: String) -> some View {
    Color(hex: background)
      .overlay(
        Circle()
          .fill(Color(hex: accent))
          .frame(width: dotSize, height: dotSize)
      )
      .frame(width: size / 2, height: size)
  }
}

// MARK: - Color hex helper (local to this file)
private extension Color {
  init(hex: String) {
    let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self.init(red: r, green: g, blue: b)
  }
}

#Preview {
  NavigationStack {
    ThemeSettingsView()
      .environmentObject(ThemeManager.shared)
      .environment(\.theme, Theme())
  }
}
