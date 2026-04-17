import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {

  @EnvironmentObject private var languageManager: LanguageManager
  @StateObject private var notificationManager = NotificationManager.shared
  @State private var preferences: NotificationPreferences
  @State private var activeTimePicker: ActiveTimePicker?

  /// Identifies which slot's time popover is currently presented.
  private enum ActiveTimePicker: Identifiable {
    case morning
    case evening
    var id: String {
      switch self {
      case .morning: return "morning"
      case .evening: return "evening"
      }
    }
  }

  init() {
    _preferences = State(initialValue: NotificationPreferences.load())
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.large) {

        // Permission Status Card
        permissionStatusCard

        if notificationManager.authorizationStatus != .denied {
          // Daily reminder slots — morning + evening
          dailyRemindersSection
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.large)
    }
    .themeBackground(.primary)
    .navigationTitle(appLocalizedString(Localizable.notificationSettings))
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await notificationManager.updateAuthorizationStatus()
    }
    .onAppear {
      // Reload preferences when view appears
      preferences = NotificationPreferences.load()
    }
  }

  // MARK: - Permission Status Card

  @ViewBuilder
  private var permissionStatusCard: some View {
    if notificationManager.authorizationStatus == .denied {
      // Permission denied - show how to enable
      notificationsDeniedView
        .padding(Spacing.large)
        .themeBackground(.secondary)
        .themeShadow(.medium)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
  }

  private var notificationsDeniedView: some View {
    VStack(spacing: Spacing.medium) {
      Image(systemName: "bell.slash.fill")
        .font(.system(size: 48))
        .themeText(.secondary)

      Text("notifications_disabled")
        .typography(.title2)
        .themeText(.primary)

      Text("notifications_disabled_message")
        .typography(.body)
        .themeText(.secondary)
        .multilineTextAlignment(.center)

      Button(action: {
        HapticManager.shared.light()
        notificationManager.openNotificationSettings()
      }) {
        Text("open_settings")
          .typography(.body)
          .fontWeight(.medium)
          .themeText(.primary)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.medium)
          .background(Color.theme.backgroundTertiary)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .padding(.top, Spacing.small)
    }
  }

  // MARK: - Daily Reminders Section

  private var dailyRemindersSection: some View {
    VStack(spacing: 0) {
      reminderRow(
        slot: .morning,
        title: NotificationType.morningReminder.titleKey,
        description: NotificationType.morningReminder.descriptionKey,
        enabled: preferences.morningReminderEnabled,
        time: preferences.morningReminderTime,
        toggle: { newValue in
          preferences.morningReminderEnabled = newValue
          Analytics.dailyReminderToggled(enabled: newValue)
          Task { await updatePreferences() }
          HapticManager.shared.selection()
        }
      )

      Divider()
        .padding(.leading, Spacing.medium)

      reminderRow(
        slot: .evening,
        title: NotificationType.eveningReminder.titleKey,
        description: NotificationType.eveningReminder.descriptionKey,
        enabled: preferences.eveningReminderEnabled,
        time: preferences.eveningReminderTime,
        toggle: { newValue in
          preferences.eveningReminderEnabled = newValue
          Analytics.dailyReminderToggled(enabled: newValue)
          Task { await updatePreferences() }
          HapticManager.shared.selection()
        }
      )
    }
    .themeBackground(.secondary)
    .themeShadow(.medium)
    .clipShape(RoundedRectangle(cornerRadius: 12))
  }

  private func reminderRow(
    slot: ActiveTimePicker,
    title: String,
    description: String,
    enabled: Bool,
    time: DateComponents,
    toggle: @escaping (Bool) -> Void
  ) -> some View {
    HStack(spacing: Spacing.medium) {
      VStack(alignment: .leading, spacing: Spacing.xSmall) {
        Text(LocalizedStringKey(title))
          .typography(.body)
          .fontWeight(.medium)
          .themeText(.primary)

        Text(LocalizedStringKey(description))
          .typography(.caption)
          .themeText(.secondary)
      }

      Spacer()

      VStack(spacing: 4) {
        Button(action: {
          if enabled {
            HapticManager.shared.light()
            activeTimePicker = slot
          }
        }) {
          Text(formatTime(time))
            .typography(.body)
            .fontWeight(.semibold)
            .themeText(enabled ? .primary : .tertiary)
        }
        .disabled(!enabled)
        .popover(
          isPresented: Binding(
            get: { activeTimePicker == slot },
            set: { isPresented in
              if !isPresented && activeTimePicker == slot {
                activeTimePicker = nil
              }
            }
          ),
          arrowEdge: .trailing
        ) {
          timePickerPopover(for: slot)
            .presentationCompactAdaptation(.popover)
        }

        Toggle(
          "",
          isOn: Binding(
            get: { enabled },
            set: { toggle($0) }
          )
        )
        .labelsHidden()
        .tint(Color.theme.accentPrimary)
      }
    }
    .padding(Spacing.medium)
    .contentShape(Rectangle())
  }

  // MARK: - Time Picker Popover

  private func timePickerPopover(for slot: ActiveTimePicker) -> some View {
    VStack(spacing: 0) {
      DatePicker(
        "",
        selection: Binding(
          get: {
            switch slot {
            case .morning: return dateFromComponents(preferences.morningReminderTime)
            case .evening: return dateFromComponents(preferences.eveningReminderTime)
            }
          },
          set: { newDate in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
            switch slot {
            case .morning: preferences.morningReminderTime = components
            case .evening: preferences.eveningReminderTime = components
            }
            Task { await updatePreferences() }
          }
        ),
        displayedComponents: .hourAndMinute
      )
      .datePickerStyle(.wheel)
      .labelsHidden()
      .frame(width: 280, height: 200)
      .environment(\.locale, LanguageManager.shared.locale)
    }
    .themeBackground(.secondary)
  }

  // MARK: - Helpers

  private func formatTime(_ components: DateComponents) -> String {
    let hour = components.hour ?? 20
    let minute = components.minute ?? 0
    return String(format: "%02d:%02d", hour, minute)
  }

  private func dateFromComponents(_ components: DateComponents) -> Date {
    let calendar = Calendar.current
    var dateComponents = DateComponents()
    dateComponents.hour = components.hour ?? 20
    dateComponents.minute = components.minute ?? 0
    return calendar.date(from: dateComponents) ?? Date()
  }

  private func updatePreferences() async {
    preferences.save()
    await notificationManager.updatePreferences(preferences)
  }
}
