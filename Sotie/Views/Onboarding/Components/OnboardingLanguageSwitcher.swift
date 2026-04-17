//
//  OnboardingLanguageSwitcher.swift
//  Sotie
//
//  Compact "🇬🇧 EN ▾" button shown in the top-right of the very first
//  onboarding screens. Lets users correct the auto-detected language
//  before they invest time in reading copy in the wrong language.
//
//  Sheet-presents a stripped-down language picker. On selection:
//  LanguageManager.setLanguage drives the rest of the flow because every
//  string flows through appLocalizedString.
//

import SwiftUI

struct OnboardingLanguageSwitcher: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var isPresenting = false

    var body: some View {
        Button {
            HapticManager.shared.light()
            isPresenting = true
        } label: {
            HStack(spacing: 6) {
                Text(languageManager.currentLanguage.flag)
                    .font(.system(size: 16))

                Text(languageManager.currentLanguage.shortCode)
                    .font(.system(size: 13, weight: .semibold))
                    .themeText(.primary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .themeText(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.theme.backgroundSecondary)
            )
            .overlay(
                Capsule()
                    .stroke(Color.theme.divider, lineWidth: 1)
            )
            .themeShadow(.subtle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(appLocalizedString(Localizable.language)))
        .accessibilityValue(Text(languageManager.currentLanguage.localizedName))
        .sheet(isPresented: $isPresenting) {
            OnboardingLanguagePickerSheet(
                onClose: { isPresenting = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Sheet

private struct OnboardingLanguagePickerSheet: View {
    let onClose: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared

    private var sortedLanguages: [Language] {
        Language.allCases.sorted {
            $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sortedLanguages) { language in
                        row(for: language)

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
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.medium)
            }
            .themeBackground(.primary)
            .navigationTitle(appLocalizedString(Localizable.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLocalizedString(Localizable.done)) {
                        HapticManager.shared.light()
                        onClose()
                    }
                }
            }
        }
    }

    private func row(for language: Language) -> some View {
        let isSelected = languageManager.currentLanguage == language

        return Button {
            if !isSelected {
                HapticManager.shared.light()
                languageManager.setLanguage(language)
                Analytics.languageChanged(to: language.code)
                Analytics.onboardingLanguageSelected(code: language.code)
            }
            onClose()
        } label: {
            HStack(spacing: Spacing.medium) {
                Text(language.flag)
                    .font(.title3)

                Text(language.localizedName)
                    .typography(.body)
                    .themeText(.primary)

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
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Color.theme.backgroundPrimary.ignoresSafeArea()
        OnboardingLanguageSwitcher()
            .padding()
    }
}
