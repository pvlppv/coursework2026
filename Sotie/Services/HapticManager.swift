//
//  HapticManager.swift
//  Sotie
//
//  Centralized haptic feedback manager using Apple's best practices
//

import CoreHaptics
import os
import SwiftUI
import UIKit

/// Centralized manager for haptic feedback throughout the app
/// Uses CoreHaptics for advanced patterns and UIFeedbackGenerator for simple feedback
final class HapticManager {

  // MARK: - Singleton
  static let shared = HapticManager()

  // MARK: - Properties
  private var engine: CHHapticEngine?
  private let supportsHaptics: Bool

  // Feedback generators (reusable for performance)
  private let impactLight = UIImpactFeedbackGenerator(style: .light)
  private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
  private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
  private let impactSoft = UIImpactFeedbackGenerator(style: .soft)
  private let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
  private let selectionGenerator = UISelectionFeedbackGenerator()
  private let notificationGenerator = UINotificationFeedbackGenerator()

  // MARK: - Initialization
  private init() {
    // Check if device supports haptics
    supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    guard supportsHaptics else { return }

    // Initialize CoreHaptics engine
    do {
      engine = try CHHapticEngine()
      try engine?.start()

      // Reset engine when app becomes active
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleEngineReset),
        name: UIApplication.didBecomeActiveNotification,
        object: nil
      )

      // Handle engine stopped
      engine?.stoppedHandler = { [weak self] reason in
        AppLogger.app.info("Haptic engine stopped: \(reason.rawValue)")
        self?.restartEngine()
      }

      // Handle engine reset
      engine?.resetHandler = { [weak self] in
        AppLogger.app.info("Haptic engine reset")
        self?.restartEngine()
      }

    } catch {
      AppLogger.app.error("Failed to initialize haptic engine: \(error.localizedDescription)")
    }

    // Prepare all generators
    impactLight.prepare()
    impactMedium.prepare()
    impactHeavy.prepare()
    impactSoft.prepare()
    impactRigid.prepare()
    selectionGenerator.prepare()
    notificationGenerator.prepare()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Engine Management
  @objc private func handleEngineReset() {
    restartEngine()
  }

  private func restartEngine() {
    guard supportsHaptics else { return }

    do {
      try engine?.start()
    } catch {
      AppLogger.app.error("Failed to restart haptic engine: \(error.localizedDescription)")
    }
  }

  // MARK: - Simple Haptics (UIFeedbackGenerator)

  /// Light tap for subtle interactions (tab switches, category selection)
  func light() {
    guard supportsHaptics else { return }
    impactLight.impactOccurred()
    impactLight.prepare()
  }

  /// Soft tap for smooth interactions (slider changes, gentle buttons)
  func soft() {
    guard supportsHaptics else { return }
    impactSoft.impactOccurred()
    impactSoft.prepare()
  }

  /// Medium impact for standard buttons and interactions
  func medium() {
    guard supportsHaptics else { return }
    impactMedium.impactOccurred()
    impactMedium.prepare()
  }

  /// Rigid impact for precise interactions (menu items, toggles)
  func rigid() {
    guard supportsHaptics else { return }
    impactRigid.impactOccurred()
    impactRigid.prepare()
  }

  /// Heavy impact for important actions (save, delete, create)
  func heavy() {
    guard supportsHaptics else { return }
    impactHeavy.impactOccurred()
    impactHeavy.prepare()
  }

  /// Selection feedback for picker-like interactions
  func selection() {
    guard supportsHaptics else { return }
    selectionGenerator.selectionChanged()
    selectionGenerator.prepare()
  }

  /// Success notification (streak achieved, tracker created)
  func success() {
    guard supportsHaptics else { return }
    notificationGenerator.notificationOccurred(.success)
    notificationGenerator.prepare()
  }

  /// Warning notification (validation issues)
  func warning() {
    guard supportsHaptics else { return }
    notificationGenerator.notificationOccurred(.warning)
    notificationGenerator.prepare()
  }

  /// Error notification (deletion, errors)
  func error() {
    guard supportsHaptics else { return }
    notificationGenerator.notificationOccurred(.error)
    notificationGenerator.prepare()
  }

  // MARK: - Streaming Haptics

  /// Last time a stream tick haptic was fired (for throttling)
  private var lastStreamTickTime: CFAbsoluteTime = 0
  /// Minimum interval between stream tick haptics (seconds)
  private let streamTickInterval: CFAbsoluteTime = 0.08

  /// Ultra-light haptic tick for AI text streaming.
  /// Throttled to fire at most once per ~80ms to avoid Taptic Engine overload
  /// when chunks arrive rapidly. Creates a pleasant "typing" texture.
  func streamTick() {
    guard supportsHaptics else { return }

    let now = CFAbsoluteTimeGetCurrent()
    guard now - lastStreamTickTime >= streamTickInterval else { return }
    lastStreamTickTime = now

    impactSoft.impactOccurred(intensity: 0.4)
    impactSoft.prepare()
  }

  /// Satisfying finish haptic when AI streaming completes.
  /// Uses UIKit feedback generators, matching stream ticks, so completion
  /// still works if the Core Haptics engine has stopped or reset.
  func streamEnd() {
    guard supportsHaptics else { return }

    // Reset throttle state
    lastStreamTickTime = 0

    notificationGenerator.notificationOccurred(.success)
    notificationGenerator.prepare()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [impactMedium] in
      impactMedium.impactOccurred(intensity: 0.65)
      impactMedium.prepare()
    }
  }

  // MARK: - Custom Haptic Patterns (CoreHaptics)

  /// Playful pattern for streak milestones and achievements
  func celebration() {
    guard supportsHaptics, let engine = engine else { return }

    var events = [CHHapticEvent]()

    // Rising pattern: 3 quick impacts with increasing intensity
    for i in 0..<3 {
      let intensity = CHHapticEventParameter(
        parameterID: .hapticIntensity,
        value: Float(0.6 + Double(i) * 0.2)
      )
      let sharpness = CHHapticEventParameter(
        parameterID: .hapticSharpness,
        value: Float(0.5 + Double(i) * 0.2)
      )
      let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [intensity, sharpness],
        relativeTime: Double(i) * 0.1
      )
      events.append(event)
    }

    playPattern(events: events, engine: engine)
  }

  /// Gentle bump for opening cards and expanding views
  func gentle() {
    guard supportsHaptics, let engine = engine else { return }

    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)

    let event = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [intensity, sharpness],
      relativeTime: 0
    )

    playPattern(events: [event], engine: engine)
  }

  /// Double tap pattern for confirmations
  func doubleTap() {
    guard supportsHaptics, let engine = engine else { return }

    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)

    let tap1 = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [intensity, sharpness],
      relativeTime: 0
    )

    let tap2 = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [intensity, sharpness],
      relativeTime: 0.1
    )

    playPattern(events: [tap1, tap2], engine: engine)
  }

  /// Increasing intensity pattern for important actions
  func crescendo() {
    guard supportsHaptics, let engine = engine else { return }

    var events = [CHHapticEvent]()

    for i in 0..<2 {
      let intensity = CHHapticEventParameter(
        parameterID: .hapticIntensity,
        value: Float(0.5 + Double(i) * 0.3)
      )
      let sharpness = CHHapticEventParameter(
        parameterID: .hapticSharpness,
        value: Float(0.3 + Double(i) * 0.3)
      )
      let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [intensity, sharpness],
        relativeTime: Double(i) * 0.08
      )
      events.append(event)
    }

    playPattern(events: events, engine: engine)
  }

  // MARK: - Helper Methods
  private func playPattern(events: [CHHapticEvent], engine: CHHapticEngine) {
    do {
      let pattern = try CHHapticPattern(events: events, parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: 0)
    } catch {
      AppLogger.app.error("Failed to play haptic pattern: \(error.localizedDescription)")
    }
  }
}

// MARK: - SwiftUI Extensions

/// View modifier for adding haptic feedback to tap gestures
struct HapticModifier: ViewModifier {
  let type: HapticType

  enum HapticType {
    case light, soft, medium, rigid, heavy
    case selection
    case success, warning, error
    case gentle, doubleTap, celebration, crescendo
  }

  func body(content: Content) -> some View {
    content
      .simultaneousGesture(
        TapGesture()
          .onEnded { _ in
            triggerHaptic()
          }
      )
  }

  fileprivate func triggerHaptic() {
    switch type {
    case .light: HapticManager.shared.light()
    case .soft: HapticManager.shared.soft()
    case .medium: HapticManager.shared.medium()
    case .rigid: HapticManager.shared.rigid()
    case .heavy: HapticManager.shared.heavy()
    case .selection: HapticManager.shared.selection()
    case .success: HapticManager.shared.success()
    case .warning: HapticManager.shared.warning()
    case .error: HapticManager.shared.error()
    case .gentle: HapticManager.shared.gentle()
    case .doubleTap: HapticManager.shared.doubleTap()
    case .celebration: HapticManager.shared.celebration()
    case .crescendo: HapticManager.shared.crescendo()
    }
  }
}

extension View {
  /// Adds haptic feedback to view taps
  func haptic(_ type: HapticModifier.HapticType) -> some View {
    modifier(HapticModifier(type: type))
  }

  /// Triggers haptic feedback programmatically
  func triggerHaptic(_ type: HapticModifier.HapticType) {
    HapticModifier(type: type).triggerHaptic()
  }

  /// Adds automatic haptic feedback to buttons based on context
  func withButtonHaptic(_ type: HapticModifier.HapticType = .light) -> some View {
    self.simultaneousGesture(
      TapGesture()
        .onEnded { _ in
          HapticModifier(type: type).triggerHaptic()
        }
    )
  }

  /// Adds haptic feedback to navigation buttons
  func withNavigationHaptic() -> some View {
    withButtonHaptic(.soft)
  }

  /// Adds haptic feedback to primary action buttons
  func withPrimaryActionHaptic() -> some View {
    withButtonHaptic(.medium)
  }

  /// Adds haptic feedback to destructive buttons
  func withDestructiveHaptic() -> some View {
    withButtonHaptic(.warning)
  }

  /// Adds haptic feedback to selection changes (toggles, pickers)
  func withSelectionHaptic() -> some View {
    withButtonHaptic(.selection)
  }
}
