//
//  ComposeSheet.swift
//  Sotie
//
//  Floating compose bar — a styled "mini sheet" overlaid on the home
//  screen via a `ZStack(alignment: .bottom)` in `MainTabView`. Tapping
//  it presents AddEntryView as a standard full-height sheet. No
//  multi-detent, no content swap, no UIKit bridging — just a button
//  that opens a sheet.
//
//  The list scrolls under the bar; `HomeView` declares
//  `contentMargins(.bottom, ComposeBar.totalHeight)` so the last entry
//  stays clear of the bar when scrolled to the bottom. The bar's frame
//  has a fixed `totalHeight` (content + 34pt home-indicator zone) so
//  the host's contentMargins can match it without any frame inference.
//

import SwiftUI

// MARK: - Environment Keys (kept for AddEntryView compatibility)

private struct ComposeCollapseAction: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

private struct ComposeIsExpandedKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  var composeCollapse: (() -> Void)? {
    get { self[ComposeCollapseAction.self] }
    set { self[ComposeCollapseAction.self] = newValue }
  }
  var composeIsExpanded: Bool {
    get { self[ComposeIsExpandedKey.self] }
    set { self[ComposeIsExpandedKey.self] = newValue }
  }
}

// MARK: - Compose Bar

/// Input bar styled as a mini sheet pinned to the bottom screen edge.
///
/// Hosted as a `ZStack(alignment: .bottom)` overlay in `MainTabView`.
/// The host applies `contentMargins(.bottom, totalHeight, for: .scrollContent)`
/// to the underlying List so its scroll content can travel exactly the
/// bar's height, keeping the last entry visible above the bar.
///
/// Layout: sheet-like rounded container with grabber on top and an
/// embedded "input field" pill below. The pill uses a contrasting
/// surface (`backgroundTertiary`) to read clearly as a tappable
/// text-entry affordance — same two-tier pattern Apple uses for
/// quick-capture surfaces in Reminders and Notes.
///
/// **Why a fixed `totalHeight`?** SwiftUI Buttons (with `.buttonStyle(.plain)`
/// and trailing label padding) under-report their frame to parents in
/// some inferred-layout contexts — manifesting as a list inset shorter
/// than the bar's visual frame. Hardcoding the height removes the
/// ambiguity. iOS 26's deployment floor (iPhone XS+) guarantees a 34pt
/// home indicator on every device.
///
/// The grabber up top is a *sheet metaphor*: it signals "tap to expand
/// into a sheet," matching the actual `.sheet(isPresented:)` that fires
/// on tap. Drag-to-expand is intentionally not wired — the metaphor is
/// purely visual, mirroring Apple Maps' search card.
///
/// Elevation comes mostly from the inner pill's contrast against the
/// outer card surface; the outer drop shadow uses `theme.shadow` (8%
/// black light, 50% dark) just to separate from the list above.
struct ComposeBar: View {
  let action: () -> Void

  /// Home-indicator height on iOS 26 iPhones.
  private static let homeIndicatorHeight: CGFloat = 34

  /// Pill height (input affordance) — sized for a single .body line
  /// with comfortable vertical padding.
  private static let pillHeight: CGFloat = 56

  /// Bar content (grabber + pill + their padding), excluding home indicator.
  ///   grabber row:    Spacing.small (top) + 5 (capsule) + Spacing.small (bottom) = 29
  ///   pill section:   Spacing.xSmall (top) + pillHeight (56) + Spacing.medium (bottom) = 80
  private static let contentHeight: CGFloat = 29 + Spacing.xSmall + pillHeight + Spacing.medium  // 109

  /// Total bar height. Read by `HomeView.contentMargins(.bottom, ...)`
  /// so the List inset matches the bar's visual frame exactly.
  static let totalHeight: CGFloat = contentHeight + homeIndicatorHeight  // 143

  private static let topRadius: CGFloat = 32
  private var sheetShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: Self.topRadius,
      bottomLeadingRadius: 0,
      bottomTrailingRadius: 0,
      topTrailingRadius: Self.topRadius,
      style: .continuous
    )
  }

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        // Grabber — signals sheet metaphor (tap to expand).
        Capsule()
          .fill(Color.theme.textTertiary.opacity(0.5))
          .frame(width: 36, height: 5)
          .padding(.top, Spacing.small)
          .padding(.bottom, Spacing.small)

        // Input pill — a tappable affordance that reads as a text field
        // even though the whole bar is the actual button.
        HStack(spacing: Spacing.small) {
          Image(systemName: "text.alignleft")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Color.theme.textSecondary)

          Text(appLocalizedString(Localizable.notePlaceholderInitial))
            .font(.body)
            .foregroundStyle(Color.theme.textSecondary)
            .lineLimit(1)

          Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.medium)
        .frame(maxWidth: .infinity)
        .frame(height: Self.pillHeight)
        .background {
          RoundedRectangle(cornerRadius: Spacing.cornerRadiusSmall, style: .continuous)
            .fill(Color.theme.inputBackground)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.xSmall)
        .padding(.bottom, Spacing.medium)

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .contentShape(Rectangle())
    }
    .buttonStyle(ComposeBarButtonStyle())
    .frame(height: Self.totalHeight)
    .background {
      // Shadow attached directly to the sheet shape so it does NOT
      // propagate to the inner pill (SwiftUI's `.shadow` modifier is
      // inherited by descendants with their own backgrounds).
      sheetShape
        .fill(Color.theme.cardBackground)
        .shadow(color: Color.theme.shadow, radius: 12, x: 0, y: -4)
    }
    .accessibilityLabel(Text("add_entry"))
  }
}

// MARK: - Press Feedback Style

/// Subtle press state for the compose bar — slight scale + opacity dip
/// so the whole surface feels responsive on tap. Animation is short
/// enough to feel snappy without competing with the sheet presentation
/// that follows.
private struct ComposeBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
      .opacity(configuration.isPressed ? 0.92 : 1.0)
      .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
  }
}

// MARK: - Preview

#Preview {
  ZStack(alignment: .bottom) {
    Color.theme.backgroundPrimary.ignoresSafeArea()
    ComposeBar(action: {})
  }
  .ignoresSafeArea(edges: .bottom)
}
