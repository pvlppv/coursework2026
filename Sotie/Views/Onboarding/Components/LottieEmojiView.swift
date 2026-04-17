//
//  LottieEmojiView.swift
//  Sotie
//
//  High-fidelity emoji animation using DotLottie (LottieFiles player).
//  Renders .lottie files with full visual fidelity.
//  Overrides framerate to 60fps for smooth playback on ProMotion displays.
//

import SwiftUI
import DotLottie

struct LottieEmojiView: View {
    let name: String
    let size: CGFloat

    @StateObject private var animation: DotLottieAnimation

    init(name: String, size: CGFloat) {
        self.name = name
        self.size = size
        _animation = StateObject(wrappedValue: DotLottieAnimation(
            fileName: name,
            config: AnimationConfig(
                autoplay: true,
                loop: true,
                speed: 1.0,
                useFrameInterpolation: true
            )
        ))
    }

    var body: some View {
        animation.view()
            .frame(width: size, height: size)
            .onAppear {
                animation.framerate = 60
            }
    }
}

#Preview {
    VStack(spacing: 24) {
        LottieEmojiView(name: "rolling_eyes_emoji", size: 120)
        LottieEmojiView(name: "star_strike_emoji", size: 120)
    }
}
