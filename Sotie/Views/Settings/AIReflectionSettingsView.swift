import SwiftUI

struct AIReflectionSettingsView: View {
  @State private var settings = AIReflectionSettingsStore.load()

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.xLarge) {
        // MARK: - Tone of Voice
        VStack(spacing: Spacing.medium) {
          sectionHeader(appLocalizedString(Localizable.aiSettingsSupportStyle))

          Text(appLocalizedString(Localizable.aiSettingsSupportStyleDescription))
            .typography(.subheadline)
            .themeText(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.medium)

          VStack(spacing: 0) {
            ForEach(Array(AIReflectionSupportStyle.allCases.enumerated()), id: \.element.id) { index, style in
              Button {
                HapticManager.shared.light()
                settings.supportStyle = style
              } label: {
                HStack(spacing: Spacing.medium) {
                  Text(appLocalizedString(style.titleKey))
                    .typography(.body)
                    .themeText(.primary)

                  Spacer()

                  if settings.supportStyle == style {
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

              if index < AIReflectionSupportStyle.allCases.count - 1 {
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

        // MARK: - How Deep to Go
        VStack(spacing: Spacing.medium) {
          sectionHeader(appLocalizedString(Localizable.aiSettingsSupportDepth))

          Text(appLocalizedString(Localizable.aiSettingsSupportDepthDescription))
            .typography(.subheadline)
            .themeText(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.medium)

          VStack(spacing: 0) {
            ForEach(Array(AIReflectionSupportDepth.allCases.enumerated()), id: \.element.id) { index, depth in
              Button {
                HapticManager.shared.light()
                settings.supportDepth = depth
              } label: {
                HStack(spacing: Spacing.medium) {
                  Text(appLocalizedString(depth.titleKey))
                    .typography(.body)
                    .themeText(.primary)

                  Spacer()

                  if settings.supportDepth == depth {
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

              if index < AIReflectionSupportDepth.allCases.count - 1 {
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

        // MARK: - What You're Here For
        VStack(spacing: Spacing.medium) {
          sectionHeader(appLocalizedString(Localizable.aiSettingsPrimaryGoals))

          Text(appLocalizedString(Localizable.aiSettingsPrimaryGoalsDescription))
            .typography(.subheadline)
            .themeText(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.medium)

          VStack(spacing: 0) {
            ForEach(Array(AIReflectionPrimaryGoal.allCases.enumerated()), id: \.element.id) { index, goal in
              Button {
                HapticManager.shared.light()
                toggleGoal(goal)
              } label: {
                HStack(spacing: Spacing.medium) {
                  Text(appLocalizedString(goal.titleKey))
                    .typography(.body)
                    .themeText(.primary)

                  Spacer()

                  if settings.primaryGoals.contains(goal) {
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

              if index < AIReflectionPrimaryGoal.allCases.count - 1 {
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
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.large)
    }
    .themeBackground(.primary)
    .navigationTitle(appLocalizedString(Localizable.aiSettingsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: settings) { _, newValue in
      AIReflectionSettingsStore.save(newValue)
    }
  }

  // MARK: - Section Header
  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .typography(.title3)
      .fontWeight(.semibold)
      .themeText(.primary)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, Spacing.medium)
  }

  private func toggleGoal(_ goal: AIReflectionPrimaryGoal) {
    if settings.primaryGoals.contains(goal) {
      guard settings.primaryGoals.count > 1 else { return }
      settings.primaryGoals.removeAll { $0 == goal }
    } else {
      settings.primaryGoals.append(goal)
    }
  }
}

#Preview {
  NavigationStack {
    AIReflectionSettingsView()
  }
}
