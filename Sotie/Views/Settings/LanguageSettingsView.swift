import SwiftUI

@MainActor
struct LanguageSettingsView: View {
  @EnvironmentObject private var languageManager: LanguageManager
  @State private var selectedLanguage: Language

  init() {
    // Initialize with current language
    _selectedLanguage = State(initialValue: LanguageManager.shared.currentLanguage)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.large) {
        // Language Selection Section
        VStack(spacing: 0) {
          ForEach(sortedLanguages) { language in
            languageRow(for: language)

            if language != sortedLanguages.last {
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
        .onAppear {
          // Sync selected language with current language
          selectedLanguage = languageManager.currentLanguage
        }
        .onChange(of: languageManager.currentLanguage) { oldValue, newValue in
          selectedLanguage = newValue
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.large)
    }
    .themeBackground(.primary)
    .navigationTitle(appLocalizedString(Localizable.language))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var sortedLanguages: [Language] {
    Language.allCases
      .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }
  }

  // MARK: - Language Row
  private func languageRow(for language: Language) -> some View {
    Button {
        if selectedLanguage != language {
          HapticManager.shared.light()
          selectedLanguage = language
          languageManager.setLanguage(language)
          Analytics.languageChanged(to: language.code)
        }
      } label: {
      HStack(spacing: Spacing.medium) {
        // Flag for quick visual recognition
        Text(language.flag)
          .font(.title3)

        // Language name
        Text(language.localizedName)
          .typography(.body)
          .themeText(.primary)

        Spacer()

        // Checkmark for selected language
        if selectedLanguage == language {
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

#Preview {
  NavigationStack {
    LanguageSettingsView()
      .environmentObject(LanguageManager.shared)
      .environment(\.theme, Theme())
  }
}
