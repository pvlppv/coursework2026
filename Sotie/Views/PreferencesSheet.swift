import StoreKit
import SwiftData
import os
import SwiftUI
import UniformTypeIdentifiers


struct PreferencesSheet: View {
  @EnvironmentObject private var router: NavigationRouter
  @EnvironmentObject private var appViewModel: AppViewModel
  @EnvironmentObject private var languageManager: LanguageManager
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

  @StateObject private var premiumManager = PremiumManager.shared
  @State private var showPaywall = false
#if DEBUG
  @State private var debugInstallID = ""
#endif

  // Import/Export states
  @State private var showExportDialog = false
  @State private var showImportPicker = false
  @State private var showImportConfirmation = false
  @State private var exportDocument: ExportDocument?
  @State private var alertTitle = ""
  @State private var alertMessage = ""
  @State private var showAlert = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color.theme.backgroundPrimary.ignoresSafeArea()

        ScrollView {
          VStack(spacing: Spacing.large) {
            // MARK: - Premium Section
            premiumSection

            // MARK: - Preferences Section
            VStack(spacing: 0) {
              NavigationLink(destination: AIReflectionSettingsView()) {
                settingsRow(
                  icon: "sparkles",
                  title: appLocalizedString(Localizable.aiSettingsTitle)
                )
              }

              Divider()
                .background(Color.theme.divider)
                .padding(.horizontal, Spacing.medium)

              NavigationLink(destination: NotificationSettingsView()) {
                settingsRow(
                  icon: "bell.fill",
                  title: appLocalizedString(Localizable.notifications)
                )
              }

              Divider()
                .background(Color.theme.divider)
                .padding(.horizontal, Spacing.medium)

              NavigationLink(destination: LanguageSettingsView()) {
                settingsRow(
                  icon: "globe",
                  title: appLocalizedString(Localizable.language)
                )
              }

              Divider()
                .background(Color.theme.divider)
                .padding(.horizontal, Spacing.medium)

              NavigationLink(destination: ThemeSettingsView()) {
                settingsRow(
                  icon: "paintpalette.fill",
                  title: appLocalizedString(Localizable.themeSettingsTitle)
                )
              }
            }
            .background(
              RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                .fill(Color.theme.backgroundSecondary)
                .themeShadow(.medium)
            )

            // MARK: - Data Section
            VStack(spacing: Spacing.medium) {
              sectionHeader(appLocalizedString(Localizable.dataSection))

              VStack(spacing: 0) {
                // Privacy Info
                HStack(spacing: Spacing.medium) {
                  Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .themeText(.primary)
                    .frame(width: 32, height: 32)

                  VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(appLocalizedString(Localizable.privacyLocalStorageTitle))
                      .typography(.footnote)
                      .fontWeight(.semibold)
                      .themeText(.primary)

                    Text(appLocalizedString(Localizable.privacyLocalStorageMessage))
                      .typography(.caption2)
                      .themeText(.tertiary)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                  .background(Color.theme.divider)
                  .padding(.horizontal, Spacing.medium)

                Button {
                  HapticManager.shared.light()
                  exportEntries()
                } label: {
                  settingsRow(
                    icon: "square.and.arrow.up.fill",
                    title: appLocalizedString(Localizable.exportEntries)
                  )
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                  .background(Color.theme.divider)
                  .padding(.horizontal, Spacing.medium)

                Button {
                  HapticManager.shared.light()
                  showImportConfirmation = true
                } label: {
                  settingsRow(
                    icon: "square.and.arrow.down.fill",
                    title: appLocalizedString(Localizable.importEntries)
                  )
                }
                .buttonStyle(PlainButtonStyle())
              }
              .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                  .fill(Color.theme.backgroundSecondary)
                  .themeShadow(.medium)
              )
            }

            // MARK: - Contact Section
            VStack(spacing: Spacing.medium) {
              sectionHeader(appLocalizedString(Localizable.contact))

              VStack(spacing: 0) {
                // Contact Us
                NavigationLink(destination: ContactUsView()) {
                  settingsRow(
                    icon: "envelope.fill",
                    title: appLocalizedString(Localizable.contactUsTitle)
                  )
                }

                Divider()
                  .background(Color.theme.divider)
                  .padding(.horizontal, Spacing.medium)

                // Share Sotie
                Button {
                  HapticManager.shared.light()
                  shareApp()
                } label: {
                  settingsRow(
                    icon: "square.and.arrow.up.fill",
                    title: appLocalizedString(Localizable.shareSotie)
                  )
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                  .background(Color.theme.divider)
                  .padding(.horizontal, Spacing.medium)

                // Rate the App
                Button {
                  HapticManager.shared.light()
                  requestAppReview()
                } label: {
                  settingsRow(
                    icon: "star.fill",
                    title: appLocalizedString(Localizable.rateApp)
                  )
                }
                .buttonStyle(PlainButtonStyle())

                Divider()
                  .background(Color.theme.divider)
                  .padding(.horizontal, Spacing.medium)

                // Show Onboarding (premium only — prevents free AI demo abuse)
                #if DEBUG
                // DEBUG: always visible for testing
                Button {
                  HapticManager.shared.light()
                  // Reset demo flag so onboarding runs the full free flow again
                  PremiumManager.shared.resetOnboardingAIDemo()
                  // Dismiss settings first, then trigger onboarding after sheet animation completes
                  dismiss()
                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    hasCompletedOnboarding = false
                  }
                } label: {
                  settingsRow(
                    icon: "play.circle.fill",
                    title: "🔧 Replay Onboarding (reset demo)"
                  )
                }
                .buttonStyle(PlainButtonStyle())
                #else
                if premiumManager.subscriptionStatus.isPremium {
                  Button {
                    HapticManager.shared.light()
                    showOnboarding()
                  } label: {
                    settingsRow(
                      icon: "play.circle.fill",
                      title: appLocalizedString(Localizable.showOnboarding)
                    )
                  }
                  .buttonStyle(PlainButtonStyle())
                }
                #endif
              }
              .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                  .fill(Color.theme.backgroundSecondary)
                  .themeShadow(.medium)
              )
            }

            // MARK: - Legal Section
            VStack(spacing: Spacing.medium) {
              sectionHeader(appLocalizedString(Localizable.legal))

              VStack(spacing: 0) {
                // Privacy Policy
                Link(destination: URL(string: "https://sotie.app/privacy")!) {
                  settingsRow(
                    icon: "hand.raised.fill",
                    title: appLocalizedString(Localizable.privacyPolicy)
                  )
                }

                Divider()
                  .background(Color.theme.divider)
                  .padding(.horizontal, Spacing.medium)

                // Terms of Service
                Link(destination: URL(string: "https://sotie.app/terms")!) {
                  settingsRow(
                    icon: "doc.text.fill",
                    title: appLocalizedString(Localizable.termsOfService)
                  )
                }
              }
              .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                  .fill(Color.theme.backgroundSecondary)
                  .themeShadow(.medium)
              )
            }

#if DEBUG
            debugSection
#endif

            VStack(spacing: Spacing.xSmall) {
              Image("SplashIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xLarge)
          }
          .padding(.horizontal, Spacing.medium)
          .padding(.bottom, Spacing.xxLarge)
        }
        .scrollIndicators(.hidden)
      }
      .navigationTitle(appLocalizedString(Localizable.preferences))
      .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDragIndicator(.visible)
    .sheet(isPresented: $showPaywall) {
      PaywallView(source: .settings)
        .environmentObject(languageManager)
    }
    .fileExporter(
      isPresented: $showExportDialog,
      document: exportDocument,
      contentType: .json,
      defaultFilename: generateExportFilename()
    ) { result in
      handleExportResult(result)
    }
    .fileImporter(
      isPresented: $showImportPicker,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      handleImportResult(result)
    }
    .alert(alertTitle, isPresented: $showAlert) {
      Button(appLocalizedString(Localizable.ok), role: .cancel) {}
    } message: {
      if !alertMessage.isEmpty {
        Text(alertMessage)
      }
    }
    .alert(
      appLocalizedString(Localizable.importConfirmTitle),
      isPresented: $showImportConfirmation
    ) {
      Button(appLocalizedString(Localizable.importConfirmAction)) {
        showImportPicker = true
      }
      Button(appLocalizedString(Localizable.cancel), role: .cancel) {}
    } message: {
      Text(appLocalizedString(Localizable.importConfirmMessage))
    }
  }

  // MARK: - Premium Section

  private var premiumSection: some View {
    VStack(spacing: Spacing.medium) {
      if premiumManager.subscriptionStatus.isPremium {
        // Premium status banner
        premiumStatusBanner
      } else {
        // Upgrade banner for free users
        upgradeBanner
      }
    }
  }

  private var premiumStatusBanner: some View {
    Button {
      HapticManager.shared.light()
      openManageSubscription()
    } label: {
      VStack(spacing: Spacing.medium) {
        // Icon at top
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 48))
          .themeText(.primary)

        // Status text
        VStack(spacing: Spacing.xSmall) {
          Text(premiumManager.subscriptionStatus.displayName)
            .typography(.title3)
            .fontWeight(.bold)
            .themeText(.primary)

          Text(appLocalizedString(Localizable.premiumManageSubscription))
            .typography(.caption)
            .themeText(.tertiary)
            .padding(.top, Spacing.small)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.xLarge)
      .padding(.horizontal, Spacing.medium)
      .background(
        RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge)
          .fill(Color.theme.backgroundSecondary)
          .themeShadow(.medium)
      )
    }
    .buttonStyle(PlainButtonStyle())
  }

#if DEBUG
  private var debugSection: some View {
    VStack(spacing: Spacing.medium) {
      sectionHeader("Developer")

      VStack(alignment: .leading, spacing: Spacing.small) {
        HStack(spacing: Spacing.medium) {
          Image(systemName: "iphone.gen3")
            .font(.title2)
            .themeText(.primary)
            .frame(width: 32, height: 32)

          VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text("Install ID")
              .typography(.footnote)
              .fontWeight(.semibold)
              .themeText(.primary)

            Text(debugInstallID.isEmpty ? "Loading..." : debugInstallID)
              .typography(.caption2)
              .themeText(.tertiary)
              .textSelection(.enabled)
          }
        }

        Button {
          UIPasteboard.general.string = debugInstallID
          HapticManager.shared.light()
        } label: {
          Text("Copy install ID")
            .typography(.caption)
            .fontWeight(.semibold)
            .themeText(.primary)
        }
        .disabled(debugInstallID.isEmpty)
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.medium)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
          .fill(Color.theme.backgroundSecondary)
          .themeShadow(.medium)
      )
      .task {
        debugInstallID = SecurityManager.shared.persistentInstallationID()
      }
    }
  }
#endif

  private var upgradeBanner: some View {
    VStack(spacing: Spacing.medium) {
      // Icon at top
      Image(systemName: "sparkles")
        .font(.system(size: 48))
        .themeText(.primary)

      // Title
      Text(appLocalizedString(Localizable.premiumTitle))
        .typography(.title3)
        .fontWeight(.bold)
        .themeText(.primary)
        .multilineTextAlignment(.center)

      // Description
      Text(appLocalizedString(Localizable.premiumSubtitle))
        .typography(.body)
        .themeText(.secondary)
        .multilineTextAlignment(.center)

      // Action button
      Button {
        HapticManager.shared.light()
        showPaywall = true
      } label: {
        Text(appLocalizedString(Localizable.premiumUpgrade))
          .typography(.body)
          .fontWeight(.semibold)
          .foregroundColor(Color.theme.buttonText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Spacing.medium)
          .themeButton()
      }
      .buttonStyle(PlainButtonStyle())
      .padding(.top, Spacing.small)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.xLarge)
    .padding(.horizontal, Spacing.medium)
    .background(
      RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge)
        .fill(Color.theme.backgroundSecondary)
        .themeShadow(.medium)
    )
  }

  // MARK: - Section Header Helper
  private func sectionHeader(_ title: String) -> some View {
    Text(title.uppercased())
      .typography(.caption)
      .themeText(.tertiary)
      .fontWeight(.medium)
      .tracking(0.5)
      .frame(maxWidth: .infinity, alignment: .center)
      .padding(.horizontal, Spacing.medium)
      .padding(.bottom, Spacing.xSmall)
  }

  // MARK: - Row helper (grouped style)
  private func settingsRow(
    icon: String,
    title: String
  ) -> some View {
    HStack(spacing: Spacing.medium) {
      Image(systemName: icon)
        .font(.title2)
        .themeText(.primary)
        .frame(width: 32, height: 32)

      Text(title)
        .typography(.body)
        .themeText(.primary)
        .multilineTextAlignment(.leading)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.caption)
        .fontWeight(.semibold)
        .themeText(.tertiary)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  // MARK: - Actions
  private func showOnboarding() {
    hasCompletedOnboarding = false
    dismiss()
  }

  private func requestAppReview() {
    if let url = URL(string: "itms-apps://itunes.apple.com/app/id6761263730?action=write-review") {
      UIApplication.shared.open(url)
      return
    }

    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
      return
    }

    if #available(iOS 18.0, *) {
      AppStore.requestReview(in: windowScene)
    } else {
      SKStoreReviewController.requestReview(in: windowScene)
    }
  }

  private func openManageSubscription() {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
      return
    }

    Task {
      do {
        // Use the iOS 15+ API for managing subscriptions
        // This will show the native subscription management UI
        try await AppStore.showManageSubscriptions(in: windowScene)
      } catch {
        AppLogger.premium.error("Failed to open subscription management: \(error)")

        // Fallback: Open subscription management in Settings
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
          await MainActor.run {
            UIApplication.shared.open(url)
          }
        }
      }
    }
  }

  private func shareApp() {
    let shareText = appLocalizedString(Localizable.shareText)
    let url = URL(string: "https://sotie.app")!

    let activityController = UIActivityViewController(
      activityItems: [shareText, url],
      applicationActivities: nil
    )

    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first,
      let rootViewController = window.rootViewController
    else { return }

    if let popoverController = activityController.popoverPresentationController {
      popoverController.sourceView = window
      popoverController.sourceRect = CGRect(
        x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
      popoverController.permittedArrowDirections = []
    }

    var topController = rootViewController
    while let presentedViewController = topController.presentedViewController {
      topController = presentedViewController
    }

    topController.present(activityController, animated: true)
  }

  // MARK: - Import/Export Actions

  private func exportEntries() {
    let exportManager = ExportManager(modelContext: modelContext)

    do {
      let document = try exportManager.exportEntries()
      exportDocument = document
      showExportDialog = true
    } catch {
      alertTitle = appLocalizedString(Localizable.exportError)
      alertMessage = error.localizedDescription
      showAlert = true
    }
  }

  private func generateExportFilename() -> String {
    let dateFormatter = Foundation.DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let dateString = dateFormatter.string(from: Date())
    return "sotie_journal_data_\(dateString).json"
  }

  private func handleExportResult(_ result: Result<URL, Error>) {
    switch result {
    case .success:
      alertTitle = appLocalizedString(Localizable.exportSuccess)
      alertMessage = ""
      showAlert = true
      Analytics.dataExported()
    case .failure(let error):
      alertTitle = appLocalizedString(Localizable.exportError)
      alertMessage = error.localizedDescription
      showAlert = true
    }
  }

  private func handleImportResult(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard let url = urls.first else { return }

      do {
        let exportManager = ExportManager(modelContext: modelContext)

        // Read the document
        guard url.startAccessingSecurityScopedResource() else {
          throw NSError(
            domain: "ImportError", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Read file data directly
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportData = try decoder.decode(ExportData.self, from: data)
        let document = ExportDocument(exportData: exportData)

        let result = try exportManager.importEntries(from: document)

        alertTitle = appLocalizedString(Localizable.importSuccess)
        alertMessage = result.message
        showAlert = true
        Analytics.dataImported(entryCount: exportData.entries.count)
      } catch {
        alertTitle = appLocalizedString(Localizable.importError)
        alertMessage = error.localizedDescription
        showAlert = true
      }

    case .failure(let error):
      alertTitle = appLocalizedString(Localizable.importError)
      alertMessage = error.localizedDescription
      showAlert = true
    }
  }
}



#Preview {
  PreferencesSheet()
    .environment(\.theme, Theme())
    .environmentObject(NavigationRouter())
    .environmentObject(AppViewModel())
    .environmentObject(LanguageManager.shared)
}
