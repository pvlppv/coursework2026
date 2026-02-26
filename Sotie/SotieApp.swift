
import os
import SwiftData
import SwiftUI
import TelemetryDeck


@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let uiTestOverrides = UITestOverrides.current

    NotificationManager.shared.prepareForLaunch()



    // Security: evaluate runtime environment for backend quota/session metadata.
    SecurityManager.shared.prepareForLaunch()

    // Initialize privacy-first analytics (TelemetryDeck)
    Analytics.configure()
    Analytics.appLaunched()

    // Apply persisted theme variant + cursor color (lightweight).
    // ThemeManager.applyOnLaunch() pushes the variant trait onto the
    // active window scene so all dynamic colors resolve to the user's
    // chosen palette from the very first frame.
    ThemeManager.shared.applyOnLaunch()

    guard !uiTestOverrides.isRunningUITests else {
      return true
    }

    // Defer all heavy initialization to avoid blocking app launch
    // This runs after the app has finished launching and UI is interactive
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      Task(priority: .background) {
        AppLogger.app.info("Starting services warm-up...")
        let startTime = CFAbsoluteTimeGetCurrent()

        // Warm up AI service first (most important for UX)
        await DefaultAIService.shared.warmUp()

        // Then warm up other services that need main actor access
        // Run at low priority to not interfere with UI
        // await MainActor.run {
        // _ = VoiceRecordingManager.shared
        // _ = ImageStorageService.shared
        // }

        let endTime = CFAbsoluteTimeGetCurrent()
        AppLogger.app.info("Services warmed up in \(String(format: "%.3f", (endTime - startTime) * 1000))ms")


      }
    }

    return true
  }

}

@main
struct SotieApp: App {
  // Register app delegate for Firebase setup
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      Entry.self,
      AnalyticsData.self,
    ])

    // Configure storage with conditional CloudKit support
    let modelConfiguration: ModelConfiguration

    if DeveloperConfig.Features.cloudKitSync {
      modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: .private(DeveloperConfig.cloudKitContainerID)
      )
    } else {
      modelConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false
      )
    }

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      AppLogger.app.error("ModelContainer creation failed: \(error)")
      AppLogger.app.warning("Attempting store recovery...")

      // Attempt to backup and recreate the corrupt store
      let fileManager = FileManager.default
      if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let storeName = "default.store"
        let storeURL = appSupport.appending(path: storeName)

        // Backup corrupt store before deleting
        let backupName = "\(storeName).corrupted-\(Int(Date().timeIntervalSince1970))"
        let backupURL = appSupport.appending(path: backupName)
        if fileManager.fileExists(atPath: storeURL.path()) {
          try? fileManager.copyItem(at: storeURL, to: backupURL)
          AppLogger.app.info("Backed up corrupt store to: \(backupName)")
        }

        // Remove all store files (main + WAL + SHM)
        for ext in ["", "-wal", "-shm"] {
          let fileURL = appSupport.appending(path: "\(storeName)\(ext)")
          try? fileManager.removeItem(at: fileURL)
        }

        // Retry with fresh store
        do {
          let freshConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
          return try ModelContainer(for: schema, configurations: [freshConfig])
        } catch {
          AppLogger.app.fault("Recovery with fresh store also failed: \(error)")
        }
      }

      // Last resort: in-memory container (app works but data won't persist across launches)
      AppLogger.app.fault("Falling back to in-memory store. Data will NOT persist.")
      do {
        let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [inMemoryConfig])
      } catch {
        // Truly unrecoverable — nothing we can do
        fatalError("Cannot create even in-memory ModelContainer: \(error)")
      }
    }
  }()

  // Owns the active palette so the trait override is reapplied on every
  // scene connection (e.g. cold launch, returning from background after a
  // memory event). Mutating `themeManager.variant` re-publishes to every
  // observer and, via `setVariant`, propagates the trait to UIKit.
  @StateObject private var themeManager = ThemeManager.shared

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.theme, Theme())
        .environmentObject(themeManager)
        .onAppear {
          // Window scene is now connected — push the persisted variant
          // trait onto the window so dynamic colors resolve correctly.
          themeManager.applyToConnectedWindows()
        }
    }
    .modelContainer(sharedModelContainer)
  }
}
