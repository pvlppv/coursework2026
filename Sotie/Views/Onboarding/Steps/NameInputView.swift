//
//  NameInputView.swift
//  Sotie
//
//  Screen 4: "what should we call you?" — keyboard-aware name input.
//  Shows explicit back button (top-left arrow).
//

import SwiftUI

struct NameInputView: View {
    @Binding var userName: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isVisible = false

    private var canContinue: Bool {
        !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.theme.backgroundPrimary
                .ignoresSafeArea()
                .onTapGesture {
                    isFocused = false
                }

            VStack(spacing: 0) {
                // Back button row
                HStack {
                    Button {
                        HapticManager.shared.soft()
                        isFocused = false
                        onBack()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.body.weight(.semibold))
                            .themeText(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(Text("Back"))
                    Spacer()
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.small)

                Spacer().frame(height: 40)

                // Labels
                VStack(alignment: .leading, spacing: 8) {
                    Text(appLocalizedString(Localizable.onboardingFlowFirstThingsFirst))
                        .typography(.subheadline)
                        .themeText(.secondary)

                    Text(appLocalizedString(Localizable.onboardingFlowNameQuestion))
                        .font(.system(size: 26, weight: .bold))
                        .themeText(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.large)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 12)

                Spacer().frame(height: 28)

                // Text field
                TextField("", text: $userName)
                    .typography(.body)
                    .themeText(.primary)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                            .fill(Color.theme.backgroundSecondary)
                    )
                    .padding(.horizontal, Spacing.large)
                    .focused($isFocused)
                    .submitLabel(.continue)
                    .onSubmit {
                        if canContinue {
                            HapticManager.shared.medium()
                            isFocused = false
                            onContinue()
                        }
                    }
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 8)

                Spacer()

                // Continue button
                OnboardingPrimaryButton(
                    appLocalizedString(Localizable.onboardingFlowContinue),
                    isEnabled: canContinue,
                    action: {
                        isFocused = false
                        onContinue()
                    }
                )
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.large)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 12)
            }
        }
        .onAppear {
            HapticManager.shared.gentle()
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                isVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isFocused = true
            }
        }
    }
}

#Preview {
    @Previewable @State var name = "Paul"
    NameInputView(userName: $name, onBack: {}, onContinue: {})
        .environment(\.theme, Theme())
}
