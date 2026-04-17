import SwiftData
import os
import SwiftUI

struct HomeView: View {
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var router: NavigationRouter
  @EnvironmentObject private var dashboardViewModel: DashboardViewModel
  @EnvironmentObject private var languageManager: LanguageManager
  @Query(sort: \Entry.date, order: .reverse) private var entries: [Entry]
  @StateObject private var premiumManager = PremiumManager.shared

  // Cache for entry count to avoid excessive onChange triggers
  @State private var lastKnownEntryCount: Int = 0
  @State private var showPaywall = false
  @State private var entryPendingDeletion: Entry?
  @State private var showingDeleteAlert = false

  /// Computed each render. SwiftData's @Query re-emits when any tracked
  /// `Entry` property changes (conversationJSON included), so this stays
  /// fresh when users add Go Deeper turns without creating a new entry.
  /// Cost: O(N entries × M user messages); Entry caches decoded conversation.
  private var reflectedDays: Set<Date> {
    ReflectionSignals.reflectedDays(from: entries)
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          // Week banner — its own Section so iOS draws the same rounded
          // card chrome (corners + soft system shadow + horizontal inset)
          // as the entry sections below. Scrolls with the content; nothing
          // pinned. Inset/background mirror the entry rows in
          // `GroupedEntriesView`.
          Section {
            WeekReflectionBanner(
              reflectedDays: reflectedDays,
              onTap: {
                router.presentSheet(.reflectionsCalendar)
              }
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.theme.backgroundSecondary)
            .listRowSeparator(.hidden)
          }

          // Entries feed
          if entries.isEmpty {
            Section {
              GroupedEntriesView(
                entries: entries,
                onTapEntry: { entry in router.presentSheet(.editEntry(entry: entry)) },
                onDeleteEntry: confirmDeleteEntry
              )
              .listRowBackground(Color.clear)
              .listRowSeparator(.hidden)
            }
          } else {
            GroupedEntriesView(
              entries: entries,
              onTapEntry: { entry in router.presentSheet(.editEntry(entry: entry)) },
              onDeleteEntry: confirmDeleteEntry
            )
          }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(Spacing.small)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .themeBackground(.primary)
        .environment(\.defaultMinListHeaderHeight, 0)
        // Reserve scroll space behind the floating ComposeBar in
        // `MainTabView`. Without this the last entry sits behind the bar
        // when scrolled to the bottom. `contentMargins` (iOS 17+) is the
        // proper API for "scroll under floating overlay" — it inset's
        // the scrollable content while leaving toolbars/headers untouched,
        // unlike `padding` (clips the whole list) or `safeAreaInset`
        // (under-measures Button frames in our case).
        .contentMargins(.bottom, ComposeBar.totalHeight, for: .scrollContent)
        // Match the gap between toolbar and banner to the gap between
        // sections (`.listSectionSpacing(Spacing.small)` = 12pt). This
        // makes the banner feel like one of the date groups visually,
        // with consistent vertical rhythm all the way down. The default
        // `.insetGrouped` top inset is ~24pt — we override it.
        .contentMargins(.top, Spacing.small, for: .scrollContent)
        .alert(
          "delete_entry_title",
          isPresented: $showingDeleteAlert
        ) {
          Button("cancel", role: .cancel) {
            entryPendingDeletion = nil
          }
          Button("delete", role: .destructive) {
            if let entry = entryPendingDeletion {
              deleteEntry(entry)
            }
            entryPendingDeletion = nil
          }
        } message: {
          Text("delete_entry_message")
        }
        .onAppear {
          // Initialize entry count cache
          lastKnownEntryCount = entries.count

          if let entryId = router.entryScrollTarget {
            scrollToEntry(entryId, with: proxy)
          }
        }
        .onChange(of: entries.count) { _, newCount in
          // Only trigger if count actually changed (not just view refresh)
          guard newCount != lastKnownEntryCount else { return }
          lastKnownEntryCount = newCount

          // Refresh dashboard stats asynchronously
          Task(priority: .utility) {
            await MainActor.run {
              dashboardViewModel.updateProgress()
            }
          }
        }
        .onChange(of: router.entryScrollTarget) { _, entryId in
          guard let entryId else { return }
          scrollToEntry(entryId, with: proxy)
        }
      }
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              HapticManager.shared.light()
              router.presentSheet(.settings)
            } label: {
              Label("preferences", systemImage: "gearshape.fill")
            }
          }
        }
        .id(languageManager.currentLanguage.code)
    }
    .sheet(isPresented: $showPaywall) {
      PaywallView(source: .settings)
    }
  }





  // MARK: - Helper Functions
  private func deleteEntry(_ entry: Entry) {
    HapticManager.shared.error()
    let entryId = entry.id
    modelContext.delete(entry)

    do {
      try modelContext.save()
      Task {
        NotificationScheduler.shared.cancelFollowUpForEntry(entryId)
        await NotificationScheduler.shared.refreshReEngagementNotifications()
      }
    } catch {
      AppLogger.data.error("Failed to delete entry: \(error)")
    }
  }

  private func confirmDeleteEntry(_ entry: Entry) {
    entryPendingDeletion = entry
    showingDeleteAlert = true
  }

  private func scrollToEntry(_ entryId: UUID, with proxy: ScrollViewProxy) {
    Task { @MainActor in
      // Two attempts: immediate + one retry after SwiftData settles
      for attempt in 0..<2 {
        if attempt > 0 {
          try? await Task.sleep(nanoseconds: 200_000_000)
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
          proxy.scrollTo(entryId, anchor: .center)
        }
      }

      router.clearEntryScrollTarget(entryId)
    }
  }
}

#Preview {
  HomeView()
    .environment(\.theme, Theme())
    .environmentObject(NavigationRouter())
    .environmentObject(DashboardViewModel())
    .modelContainer(for: Entry.self, inMemory: true)
}
