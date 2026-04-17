import SwiftUI

/// Unified empty-state view used across surfaces (home feed, analytics,
/// prototype). The three call sites previously hand-rolled their own
/// VStack + icon arrangements with inconsistent spacing — `xLarge`
/// between icon and title here, `large` there. This component is the
/// single source of truth.
///
/// Visual decisions:
///   • Big, bold icon — matches the modern editorial empty-state
///     language Apple uses in Wallet, Notes, Mail, Files. 80pt at
///     `.thin` weight gives the screen a confident centerpiece without
///     feeling cartoonish.
///   • Tight typographic rhythm: 12pt between icon and title, 8pt
///     between title and description. The previous 32pt + 16pt
///     spacing made the three elements read as separate islands;
///     this tightens them into one composition while still letting
///     the icon breathe at the top.
///   • Title in `.largeTitle.bold` — confident, headline-scale.
///     Description in `textSecondary` body keeps a clear hierarchy
///     without dimming the message into invisibility.
struct EmptyStateView: View {

  // MARK: - Configuration

  let icon: String
  let title: LocalizedStringKey
  let description: LocalizedStringKey?

  init(
    icon: String,
    title: LocalizedStringKey,
    description: LocalizedStringKey? = nil
  ) {
    self.icon = icon
    self.title = title
    self.description = description
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: icon)
        .font(.system(size: 80, weight: .thin).leading(.tight))
        .foregroundColor(Color.theme.accentPrimary)

      Spacer().frame(height: Spacing.small) // 12pt — icon → title

      Text(title)
        .font(.largeTitle.weight(.bold))
        .foregroundColor(Color.theme.textPrimary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.large)
        .fixedSize(horizontal: false, vertical: true)

      if let description {
        Spacer().frame(height: Spacing.xSmall) // 8pt — title → body

        Text(description)
          .font(.body)
          .foregroundColor(Color.theme.textSecondary)
          .multilineTextAlignment(.center)
          .lineSpacing(4)
          .padding(.horizontal, Spacing.xLarge)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview("With description") {
  EmptyStateView(
    icon: "pencil.line",
    title: "empty_state_title",
    description: "empty_state_description"
  )
  .environment(\.theme, Theme())
}

#Preview("No description") {
  EmptyStateView(
    icon: "chart.bar",
    title: "analytics_no_data"
  )
  .environment(\.theme, Theme())
}
