//
//  OnboardingProgressBar.swift
//  Sotie
//
//  Thin progress bar shown at the top of screens 11+.
//  Animates smoothly between steps.
//

import SwiftUI

struct OnboardingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.theme.backgroundTertiary)
                    .frame(height: 4)

                // Fill
                Capsule()
                    .fill(Color.theme.textPrimary)
                    .frame(width: geo.size.width * progress, height: 4)
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 4)
    }
}

#Preview {
    VStack(spacing: 20) {
        OnboardingProgressBar(progress: 0.33)
        OnboardingProgressBar(progress: 0.66)
        OnboardingProgressBar(progress: 1.0)
    }
    .padding()
    .background(Color.theme.backgroundPrimary)
}
