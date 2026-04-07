import Combine
import SwiftData
import SwiftUI

// Root view model coordinating app-wide state
@MainActor
class AppViewModel: ObservableObject {
  @Published var userSession: UserSession?
  @Published var isInitialized: Bool = false

  private var modelContext: ModelContext?

  // MARK: - Initialization
  func initialize(with modelContext: ModelContext) {
    self.modelContext = modelContext
    loadUserSession()
    isInitialized = true
  }

  // MARK: - User Session Management
  private func loadUserSession() {
    userSession = UserSession(
      userId: UUID(),
      createdAt: Date(),
      lastActiveAt: Date()
    )
  }

  // MARK: - AI Feature Gating
  func isAIFeatureAvailable() -> Bool {
    return DeveloperConfig.AI.enabled
  }

  // MARK: - App State Management
  func resetAppState() {
    userSession = nil
    isInitialized = false
  }
}

// User session model
struct UserSession {
  let userId: UUID
  let createdAt: Date
  var lastActiveAt: Date
}
