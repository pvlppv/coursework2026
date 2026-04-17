//
//  SurveyOptionRow.swift
//  Sotie
//
//  Reusable row for single-select survey options.
//  Full-width, generous tap target, optional leading emoji.
//  Selection: subtle background shift + border.
//

import SwiftUI

struct SurveyOptionRow: View {
    let emoji: String?
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 20))
                }

                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .themeText(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .fill(isSelected
                          ? Color.theme.backgroundTertiary
                          : Color.theme.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .stroke(isSelected
                            ? Color.theme.textPrimary.opacity(0.2)
                            : Color.clear,
                            lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        SurveyOptionRow(emoji: "🧑", title: "someone", isSelected: false, action: {})
        SurveyOptionRow(emoji: "💫", title: "what happened", isSelected: true, action: {})
        SurveyOptionRow(emoji: nil, title: "all the time and stays forever", isSelected: false, action: {})
    }
    .padding(.horizontal, 24)
    .background(Color.theme.backgroundPrimary)
}
