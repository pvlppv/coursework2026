//
//  LoopingVideoPlayer.swift
//  Sotie
//
//  Muted, looping AVPlayer wrapper for onboarding demo footage.
//  Loads a video by name from the main bundle (e.g. "demo_loop.mp4")
//  and seamlessly loops via AVPlayerLooper.
//
//  Falls back to a placeholder fill if the asset is missing so previews
//  and dev builds don't crash before the video file is added.
//

import SwiftUI
import AVKit
import AVFoundation

struct LoopingVideoPlayer: View {
    let videoName: String
    let videoExtension: String

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    init(videoName: String, videoExtension: String = "mp4") {
        self.videoName = videoName
        self.videoExtension = videoExtension
    }

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)  // No user controls
            } else {
                // Placeholder — neutral surface, no scary error
                Color.theme.backgroundTertiary
                    .overlay(
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 36, weight: .light))
                            .themeText(.tertiary)
                    )
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    private func setupPlayer() {
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: videoName, withExtension: videoExtension) else {
            return  // Falls back to placeholder
        }

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .none

        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer
        queuePlayer.play()
    }

    private func teardownPlayer() {
        player?.pause()
        looper = nil
        player = nil
    }
}

#Preview {
    LoopingVideoPlayer(videoName: "demo_loop")
        .frame(width: 240, height: 480)
}
