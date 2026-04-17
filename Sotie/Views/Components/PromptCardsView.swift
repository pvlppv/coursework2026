//
//  PromptCardsView.swift
//  Sotie
//
//  Updated on 17.05.2026 — clusters replace categories as the user-visible
//  surface; cards gain a small subtitle and trim to a narrower width.
//
//  Horizontal, scroll-snapping rail of prompt cluster cards shown above
//  the AddEntry textarea while the conversation is empty.
//

import SwiftUI

/// A single prompt cluster card. Slimmer than the previous version (108pt
/// wide) so more cards fit on screen at once. Tap selects the cluster; the
/// parent view owns the actual seeding side effect.
///
/// Selected cards swap their illustration to the picked sub-state's icon
/// (`selectedSubStateImageOverride`). This is the "icon variety" effect —
/// the same Heavy card can show heavy / numb / anxious / frustrated based
/// on which opener the picker rolled.
struct PromptCardView: View {
  let cluster: PromptCluster
  let hour: Int
  let isSelected: Bool
  let isAnyCardSelected: Bool
  let selectedSubStateImageOverride: String?
  let randomIllustration: String?
  let onTap: () -> Void

  @Environment(\.theme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPressed = false

  var body: some View {
    Button(action: onTap) {
      VStack(spacing: Spacing.xSmall) {
        // Illustration with cross-fade + tiny scale on swap. The
        // `.id(illustrationName)` makes SwiftUI treat each variant as a
        // distinct view, so the `.transition` fires on every change.
        Image(illustrationName)
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .foregroundStyle(theme.colors.textPrimary)
          .frame(maxWidth: .infinity)
          .frame(height: 84)
          .padding(.horizontal, Spacing.small)
          .id(illustrationName)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .scale(scale: 0.92)),
              removal: .opacity
            )
          )
          .animation(
            reduceMotion ? .none : .easeOut(duration: 0.22),
            value: illustrationName
          )

        // Title — lighter weight, secondary color, up to 2 lines.
        // The illustration leads; the title is quiet confirmation.
        Text(LocalizedStringResource(stringLiteral: titleKey))
          .font(.subheadline)
          .themeText(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, Spacing.xSmall)
      }
      .padding(.vertical, Spacing.medium)
      .frame(width: 108, height: 148)
      .background(cardBackground)
      .overlay(
        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
          .stroke(borderColor, lineWidth: borderWidth)
      )
      .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
      .themeShadow(.subtle)
      .scaleEffect(scale)
      .opacity(opacity)
      .animation(reduceMotion ? .none : .easeOut(duration: 0.18), value: isSelected)
      .animation(reduceMotion ? .none : .easeOut(duration: 0.12), value: isPressed)
    }
    .buttonStyle(PromptCardPressStyle(isPressed: $isPressed))
    .accessibilityLabel(Text(LocalizedStringResource(stringLiteral: titleKey)))
    .accessibilityHint(Text(LocalizedStringResource(stringLiteral: Localizable.promptsCardAccessibilityHint)))
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
  }

  // MARK: - Cluster-aware resolvers

  private var titleKey: String {
    cluster == .time ? cluster.timeTitleKey(forHour: hour) : cluster.titleKey
  }

  private var illustrationName: String {
    // Priority:
    // 1. If a sub-state was picked (via tap), use its illustration — even
    //    after deselect, so the card doesn't visually snap back.
    // 2. If a random illustration was assigned at session start, use it.
    // 3. Fall back to the cluster's static default.
    if let override = selectedSubStateImageOverride {
      return override
    }
    if let random = randomIllustration {
      return random
    }
    if cluster == .time {
      return cluster.timeIllustration(forHour: hour)
    }
    return cluster.defaultIllustration
  }

  /// Card surface color. Uses the standard elevated surface token —
  /// white in light mode lifts off the cream-grey page, elevated dark
  /// in dark mode lifts off the near-black page.
  private var cardBackground: Color {
    theme.colors.backgroundSecondary
  }

  private var borderColor: Color {
    if isSelected {
      return theme.colors.textPrimary
    }
    return theme.colors.divider
  }

  private var borderWidth: CGFloat {
    isSelected ? 1.5 : 0.5
  }

  private var scale: CGFloat {
    if isPressed { return 0.96 }
    if isSelected { return 1.02 }
    return 1.0
  }

  private var opacity: Double {
    if isAnyCardSelected && !isSelected { return 0.5 }
    return 1.0
  }
}

/// Press-state-tracking ButtonStyle for cards. We want the visual scale to
/// remain controllable from outside (selection state), so the style only
/// reports the press state up via a binding.
private struct PromptCardPressStyle: ButtonStyle {
  @Binding var isPressed: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .onChange(of: configuration.isPressed) { _, newValue in
        isPressed = newValue
      }
  }
}

/// The horizontal rail of prompt cluster cards. Owns its own ScrollView and
/// drives selection through closures — VM owns the seeded state.
struct PromptCardsRail: View {
  let clusters: [PromptCluster]
  let selectedCluster: PromptCluster?
  let selectedSubStateImageOverride: String?
  let randomIllustrations: [PromptCluster: String]
  let hour: Int
  let onSelect: (PromptCluster) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(spacing: Spacing.small) {
        ForEach(clusters, id: \.rawValue) { cluster in
          PromptCardView(
            cluster: cluster,
            hour: hour,
            isSelected: selectedCluster == cluster,
            isAnyCardSelected: selectedCluster != nil,
            selectedSubStateImageOverride: imageOverride(for: cluster),
            randomIllustration: randomIllustrations[cluster]
          ) {
            onSelect(cluster)
          }
          .id(cluster.rawValue)
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.xSmall)
      // Required by `.scrollTargetBehavior(.viewAligned)` — without this,
      // SwiftUI logs `No scroll targets were found, but the viewAligned
      // behavior was requested. Are you missing a scrollTargetLayout()?`
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.viewAligned)
  }

  /// Resolve the illustration override for a given cluster card.
  ///
  /// Two paths produce a non-nil override:
  ///   1. The cluster is currently selected → its override applies.
  ///   2. The cluster was previously selected but deselected → the override
  ///      still applies so the card visual doesn't snap back to default.
  ///
  /// We can tell #2 from #1 because `selectedCluster` is nil while the
  /// override is non-nil. Other clusters get nil so they show defaults.
  private func imageOverride(for cluster: PromptCluster) -> String? {
    guard let override = selectedSubStateImageOverride else { return nil }
    // If a cluster is selected, only that one gets the override.
    if let selected = selectedCluster {
      return selected == cluster ? override : nil
    }
    // No selection: only show the override on the cluster whose sub-states
    // include the override image. Match by imageName prefix.
    let prefix = "prompt_"
    let subStateRaw = override.hasPrefix(prefix)
      ? String(override.dropFirst(prefix.count)) : override
    if let subState = PromptCategory(rawValue: subStateRaw),
      cluster.subStates.contains(subState)
    {
      return override
    }
    return nil
  }
}

// MARK: - Prompt Rail Transition

extension AnyTransition {
  /// Slide-from-top + fade. Uses Apple's `.snappy` preset — the iOS 17
  /// system spring designed for responsive show/hide motion.
  static var promptRail: AnyTransition {
    AnyTransition.move(edge: .top)
      .combined(with: .opacity)
      .animation(.snappy)
  }
}
