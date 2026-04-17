//
//  BlurRevealRenderer.swift
//  Sotie
//
//  Per-character blur reveal animation for AI responses.
//  Uses iOS 17+ TextRenderer API for GPU-accelerated rendering.
//

import SwiftUI

/// Per-character blur reveal renderer.
///
/// Each character at index `i` begins revealing at `i × 0.012` seconds.
struct BlurRevealRenderer: TextRenderer {

  var elapsedTime: Double

  // perCharDelay × ~84 chars/sec ≈ 1.0 delay growth/sec.
  // Keep this stable for long reflections; the row controls catch-up speed.
  private let perCharDelay: Double = 0.012
  private let charRevealDuration: Double = 0.3
  private let maxBlurRadius: Double = 5
  private let maxYOffset: Double = 4

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    if elapsedTime >= completionThreshold(for: layout) {
      for line in layout { for run in line { context.draw(run) } }
      return
    }

    var charIndex = 0
    for line in layout {
      for run in line {
        for slice in run {
          let delay = Double(charIndex) * perCharDelay
          let progress = max(0, min(1, (elapsedTime - delay) / charRevealDuration))

          if progress >= 1 {
            context.draw(slice)
          } else if progress <= 0 {
            // invisible — skip
          } else {
            var copy = context
            copy.addFilter(.blur(radius: (1 - progress) * maxBlurRadius))
            copy.opacity = progress
            copy.translateBy(x: 0, y: (1 - progress) * maxYOffset)
            copy.draw(slice, options: .disablesSubpixelQuantization)
          }
          charIndex += 1
        }
      }
    }
  }

  func completionThreshold(for layout: Text.Layout) -> Double {
    let characterCount = layout.reduce(into: 0) { total, line in
      total += line.reduce(into: 0) { lineTotal, run in
        lineTotal += run.reduce(into: 0) { runTotal, _ in
          runTotal += 1
        }
      }
    }

    return completionThreshold(forCharacterCount: characterCount)
  }

  func completionThreshold(forCharacterCount characterCount: Int) -> Double {

    guard characterCount > 0 else { return 10 }

    return max(10, revealDuration(forCharacterCount: characterCount))
  }

  func revealDuration(forCharacterCount characterCount: Int) -> Double {
    guard characterCount > 0 else { return 0 }

    let lastCharacterDelay = Double(characterCount - 1) * perCharDelay
    return lastCharacterDelay + charRevealDuration
  }

  func estimatedVisibleCharacterCount(forElapsedTime elapsedTime: Double) -> Int {
    guard elapsedTime >= 0 else { return 0 }
    return max(0, Int(floor(elapsedTime / perCharDelay)) + 1)
  }
}
