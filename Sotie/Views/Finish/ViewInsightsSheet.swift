import SwiftUI

/// Simple read-only sheet showing previously generated insights for an entry.
struct ViewInsightsSheet: View {
  let insights: ConversationInsights

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
          Spacer()
            .frame(height: Spacing.medium)

          insightCard(
            icon: "doc.text",
            title: appLocalizedString(Localizable.insightsWhatHappened),
            content: insights.whatHappened
          )

          insightCard(
            icon: "eye",
            title: appLocalizedString(Localizable.insightsWhatsUnderneath),
            content: insights.whatsUnderneath
          )

          insightCard(
            icon: "arrow.right.circle",
            title: appLocalizedString(Localizable.insightsWhatMattersNow),
            content: insights.whatMattersNow
          )

          Spacer()
            .frame(height: Spacing.large)
        }
        .padding(.horizontal, Spacing.large)
      }
      .themeBackground(.primary)
      .navigationTitle(appLocalizedString(Localizable.insightsTitle))
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDragIndicator(.visible)
    .presentationDetents([.medium, .large])
  }

  private func insightCard(icon: String, title: String, content: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack(spacing: Spacing.xSmall) {
        Image(systemName: icon)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Color.theme.accentPrimary)

        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.theme.accentPrimary)
          .textCase(.uppercase)
      }

      Text(content)
        .typography(.body)
        .themeText(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.theme.backgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
  }
}

#Preview {
  ViewInsightsSheet(
    insights: ConversationInsights(
      whatHappened: "You were processing feedback from your manager about not being ready for a project.",
      whatsUnderneath: "A fear that the criticism confirms something you already suspect about yourself — that you're not enough.",
      whatMattersNow: "Her opinion is one data point, not a verdict. Ask yourself what 'ready' actually means to you.",
      messageCount: 6
    )
  )
  .environment(\.theme, Theme())
}
