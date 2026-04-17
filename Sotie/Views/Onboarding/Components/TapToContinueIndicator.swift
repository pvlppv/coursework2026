//
//  TapToContinueIndicator.swift
//  Sotie
//
//  Bottom-right aligned "tap to continue →" with gentle arrow pulse.
//

import SwiftUI

struct TapToContinueIndicator: View {
    @State private var arrowOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            Text(appLocalizedString(Localizable.onboardingFlowTapToContinue))
                .typography(.bodyEmphasized)
                .themeText(.secondary)

            Image(systemName: "arrow.right")
                .font(.body.weight(.semibold))
                .themeText(.secondary)
                .offset(x: arrowOffset)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                .repeatForever(autoreverses: true)
            ) {
                arrowOffset = 4
            }
        }
    }
}

#Preview {
    TapToContinueIndicator()
        .padding()
        .environment(\.theme, Theme())
}
