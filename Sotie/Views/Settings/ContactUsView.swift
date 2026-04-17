//
//  ContactUsView.swift
//  Sotie
//
//  Universal contact form — message + optional logs → default email or share.
//
//

import os
import SwiftUI
import UIKit

struct ContactUsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var message = ""
  @State private var includeLogs = false
  @State private var showShareSheet = false
  @State private var shareItems: [Any] = []
  @State private var isSending = false

  private var canSend: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static let supportEmail = "support@sotie.app"

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.large) {

        // MARK: - Header
        headerSection

        // MARK: - Message
        messageSection

        // MARK: - Logs Toggle
        logsToggleSection

        // MARK: - Send
        sendButton
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.vertical, Spacing.large)
    }
    .themeBackground(.primary)
    .navigationTitle(appLocalizedString(Localizable.contactUsTitle))
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .sheet(isPresented: $showShareSheet) {
      ShareSheet(items: shareItems)
    }
  }

  // MARK: - Header

  private var headerSection: some View {
    VStack(spacing: Spacing.small) {
      Image(systemName: "envelope.fill")
        .font(.system(size: 40))
        .themeText(.secondary)
        .padding(.bottom, Spacing.xxSmall)

      Text("contact_us_subtitle")
        .typography(.body)
        .themeText(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.large)
    }
  }

  // MARK: - Message

  private var messageSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xSmall) {
      Text("contact_us_message_label")
        .typography(.footnote)
        .fontWeight(.medium)
        .themeText(.secondary)

      TextEditor(text: $message)
        .typography(.body)
        .themeText(.primary)
        .frame(minHeight: 140)
        .scrollContentBackground(.hidden)
        .padding(Spacing.small)
        .background(
          RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
            .fill(Color.theme.backgroundSecondary)
        )
        .overlay(alignment: .topLeading) {
          if message.isEmpty {
            Text("contact_us_message_placeholder")
              .typography(.body)
              .themeText(.tertiary)
              .padding(.horizontal, Spacing.small + 4)
              .padding(.vertical, Spacing.small + 8)
              .allowsHitTesting(false)
          }
        }
    }
  }

  // MARK: - Logs Toggle

  private var logsToggleSection: some View {
    HStack(spacing: Spacing.medium) {
      VStack(alignment: .leading, spacing: Spacing.xxSmall) {
        Text("contact_us_include_logs")
          .typography(.body)
          .fontWeight(.medium)
          .themeText(.primary)

        Text("contact_us_include_logs_desc")
          .typography(.caption)
          .themeText(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()

      Toggle("", isOn: $includeLogs)
        .labelsHidden()
        .tint(Color.theme.accentPrimary)
    }
    .padding(Spacing.medium)
    .background(
      RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
        .fill(Color.theme.backgroundSecondary)
        .themeShadow(.medium)
    )
  }

  // MARK: - Send Button

  private var sendButton: some View {
    Button {
      HapticManager.shared.medium()
      sendMessage()
    } label: {
      HStack(spacing: Spacing.small) {
        if isSending {
          ProgressView()
            .tint(Color.theme.textTertiary)
        }
        Text("contact_us_send")
          .typography(.body)
          .fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.medium)
      .foregroundStyle(canSend && !isSending ? Color.theme.buttonText : Color.theme.textTertiary)
      .background(
        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
          .fill(canSend && !isSending ? Color.theme.buttonBackground : Color.theme.backgroundTertiary)
      )
    }
    .disabled(!canSend || isSending)
    .animation(.easeInOut(duration: 0.2), value: canSend)
    .animation(.easeInOut(duration: 0.2), value: isSending)
  }

  // MARK: - Send Logic

  private func sendMessage() {
    isSending = true

    Task {
      // Collect logs in background if needed
      var logText: String?
      if includeLogs {
        logText = await Task.detached(priority: .userInitiated) {
          LogExporter.exportRecentLogs(hours: 24)
        }.value
      }

      await MainActor.run {
        let fullBody = composeFullBody(logs: logText)

        // 1. Try mailto: → opens default email client
        let subject = "Sotie Journal — \(appLocalizedString("contact_us_title"))"
        if let mailtoURL = buildMailtoURL(to: Self.supportEmail, subject: subject, body: fullBody),
           UIApplication.shared.canOpenURL(mailtoURL) {
          UIApplication.shared.open(mailtoURL)
          isSending = false
          return
        }

        // 2. Fallback: share sheet
        shareItems = [fullBody]
        showShareSheet = true
        isSending = false
      }
    }
  }

  // MARK: - Compose Helpers

  private func composeFullBody(logs: String? = nil) -> String {
    var body = message.trimmingCharacters(in: .whitespacesAndNewlines)

    // Compact device footer
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    body += "\n\n—\n\(deviceName) / iOS \(UIDevice.current.systemVersion) / v\(version)"

    // Diagnostic logs
    if let logs {
      body += "\n\n" + logs
    }

    return body
  }

  private func buildMailtoURL(to recipient: String, subject: String, body: String) -> URL? {
    // mailto: requires CRLF line endings per RFC 6068
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=")

    let crlfSubject = subject.replacingOccurrences(of: "\n", with: "\r\n")
    let crlfBody = body.replacingOccurrences(of: "\n", with: "\r\n")

    guard let encodedSubject = crlfSubject.addingPercentEncoding(withAllowedCharacters: allowed),
          let encodedBody = crlfBody.addingPercentEncoding(withAllowedCharacters: allowed)
    else { return nil }

    return URL(string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)")
  }

  // MARK: - Helpers

  private var deviceName: String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let modelCode = withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(validatingCString: $0) ?? "Unknown"
      }
    }
    return modelCode
  }

  private var appVersion: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
  NavigationStack {
    ContactUsView()
      .environment(\.theme, Theme())
  }
}
