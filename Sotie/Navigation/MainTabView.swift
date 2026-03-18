import SwiftData
import os
import SwiftUI

struct MainTabView: View {
  @EnvironmentObject private var router: NavigationRouter
  @EnvironmentObject private var appViewModel: AppViewModel
  @EnvironmentObject private var dashboardViewModel: DashboardViewModel
  @EnvironmentObject private var languageManager: LanguageManager
  @EnvironmentObject private var notificationManager: NotificationManager
  @Environment(\.modelContext) private var modelContext

  @State private var showAddEntry = false

  var body: some View {
    RouterSheetHost {
      ZStack(alignment: .bottom) {
        HomeView()

        ComposeBar {
          HapticManager.shared.light()
          showAddEntry = true
        }
      }
      .ignoresSafeArea(edges: .bottom)
      .onChange(of: router.presentedSheet) { oldSheet, newSheet in
          if oldSheet == nil && newSheet != nil {
            HapticManager.shared.light()
            router.sheetDidPresent()
          } else if oldSheet != nil && newSheet == nil {
            HapticManager.shared.soft()
          }

          // `.addEntry` opens the compose sheet.
          if case .addEntry = newSheet {
            showAddEntry = true
            router.dismissSheet()
          }
        }
        .environmentObject(router)
        .environmentObject(appViewModel)
        .environmentObject(dashboardViewModel)
        .preferredColorScheme(nil)
        .sheet(isPresented: $showAddEntry) {
          AddEntryView(
            onSave: { entry in
              modelContext.insert(entry)
              do {
                try modelContext.save()

                let hasAI = !entry.conversation.isEmpty
                let wordCount = entry.observation
                  .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                Analytics.entryCreated(
                  wordCount: wordCount,
                  hasAIConversation: hasAI
                )
                if hasAI {
                  ReviewManager.shared.recordAIAssistedSave()
                }

                Task {
                  await NotificationScheduler.shared.scheduleConversationFollowUp(for: entry)
                }
              } catch {
                AppLogger.data.error("Failed to save entry: \(error)")
              }
            }
          )
          .environment(\.composeIsExpanded, true)
          .environmentObject(router)
        }
    }
  }
}

// MARK: - RouterSheetHost

/// Wraps content and owns the router's `.sheet(item:)` modifier.
/// This separates the router-driven sheet presentation context from the
/// persistent compose sheet, avoiding the two-sheet-on-one-view conflict
/// that causes animation glitches in SwiftUI.
private struct RouterSheetHost<Content: View>: View {
  @EnvironmentObject private var router: NavigationRouter
  @EnvironmentObject private var appViewModel: AppViewModel
  @EnvironmentObject private var languageManager: LanguageManager
  @Environment(\.modelContext) private var modelContext

  @ViewBuilder let content: Content

  var body: some View {
    content
      .sheet(item: $router.presentedSheet, onDismiss: {
        router.sheetDidDismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          ReviewManager.shared.requestReviewIfEligible()
        }
      }) { destination in
        sheetContent(for: destination)
      }
  }

  @ViewBuilder
  private func sheetContent(for destination: SheetDestination) -> some View {
    switch destination {
    case .addEntry:
      EmptyView()
    case .editEntry(let entry):
      EditEntryView(
        entry: entry,
        onSave: { updatedEntry in
          do {
            try modelContext.save()
            router.dismissSheet()

            Task {
              await NotificationScheduler.shared.scheduleConversationFollowUp(for: updatedEntry)
            }
          } catch {
            AppLogger.data.error("Failed to save entry: \(error)")
          }
        },
        onDelete: {
          let entryId = entry.id
          modelContext.delete(entry)
          do {
            try modelContext.save()
            router.dismissSheet()

            Analytics.entryDeleted()

            Task {
              NotificationScheduler.shared.cancelFollowUpForEntry(entryId)
              await NotificationScheduler.shared.refreshReEngagementNotifications()
            }
          } catch {
            AppLogger.data.error("Failed to delete entry: \(error)")
          }
        }
      )
      .id(entry.id)
      .environmentObject(router)
      .onAppear {
        Analytics.entryOpened()
        Analytics.screenViewed("EditEntry")
      }
    case .editEntryById(let entryId):
      ResolvedEditEntrySheet(entryId: entryId)
        .environmentObject(router)
        .onAppear {
          Analytics.entryOpened()
          Analytics.screenViewed("EditEntry")
        }
    case .settings:
      PreferencesSheet()
        .environmentObject(router)
        .environmentObject(appViewModel)
        .environmentObject(languageManager)
        .onAppear { Analytics.screenViewed("Settings") }
    case .reflectionsCalendar:
      ReflectionsCalendarSheet()
        .environmentObject(languageManager)
        .presentationDragIndicator(.visible)
        .onAppear { Analytics.screenViewed("ReflectionsCalendar") }
    case .customView(let view):
      view
    }
  }
}

private struct ResolvedEditEntrySheet: View {
  let entryId: UUID

  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var router: NavigationRouter

  @State private var resolvedEntry: Entry?

  var body: some View {
    Group {
      if let resolvedEntry {
        EditEntryView(
          entry: resolvedEntry,
          onSave: { updatedEntry in
            do {
              try modelContext.save()
              router.dismissSheet()

              Task {
                await NotificationScheduler.shared.scheduleConversationFollowUp(for: updatedEntry)
              }
            } catch {
              AppLogger.data.error("Failed to save entry: \(error)")
            }
          },
          onDelete: {
            let entryId = resolvedEntry.id
            modelContext.delete(resolvedEntry)
            do {
              try modelContext.save()
              router.dismissSheet()

              // Track entry deletion
              Analytics.entryDeleted()

              Task {
                NotificationScheduler.shared.cancelFollowUpForEntry(entryId)
                await NotificationScheduler.shared.refreshReEngagementNotifications()
              }
            } catch {
              AppLogger.data.error("Failed to delete entry: \(error)")
            }
          }
        )
        .id(resolvedEntry.id)
        .environmentObject(router)
      } else {
        // Invisible — resolve synchronously on appear.
        // If entry is missing, dismiss without animation so user sees nothing.
        Color.clear
          .onAppear {
            resolveEntrySync()
          }
      }
    }
  }

  /// Synchronous entry resolution — no retries, instant result.
  /// If entry is gone (deleted), dismiss sheet without animation to avoid gray flash.
  private func resolveEntrySync() {
    guard resolvedEntry == nil else { return }

    let descriptor = FetchDescriptor<Entry>(
      predicate: #Predicate { entry in
        entry.id == entryId
      }
    )

    do {
      if let entry = try modelContext.fetch(descriptor).first {
        AppLogger.notifications.info("Entry resolved: \(entry.id)")
        resolvedEntry = entry
        return
      }
    } catch {
      AppLogger.notifications.error("Entry fetch error: \(error)")
    }

    // Entry not found — dismiss instantly (no animation = no gray sheet flash)
    AppLogger.notifications.info("Entry not found: \(entryId) — navigating home")
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      router.dismissSheet()
      router.selectTab(.home)
    }
  }
}

#Preview {
  MainTabView()
    .environmentObject(AppViewModel())
    .environmentObject(DashboardViewModel())
    .environmentObject(LanguageManager.shared)
    .environmentObject(NavigationRouter())
    .environmentObject(NotificationManager.shared)
    .environment(\.theme, Theme())
    .modelContainer(for: Entry.self, inMemory: true)
}
