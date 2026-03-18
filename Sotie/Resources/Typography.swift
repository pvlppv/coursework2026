import SwiftUI

// MARK: - Typography System
struct Typography {

  // MARK: - Font Styles
  static let largeTitle = Font.largeTitle.weight(.bold)
  static let title = Font.title.weight(.semibold)
  static let title2 = Font.title2.weight(.semibold)
  static let title3 = Font.title3.weight(.medium)

  static let headline = Font.headline.weight(.medium)
  static let subheadline = Font.subheadline.weight(.medium)

  static let body = Font.body
  static let bodyEmphasized = Font.body.weight(.medium)

  static let callout = Font.callout
  static let calloutEmphasized = Font.callout.weight(.medium)

  static let footnote = Font.footnote
  static let caption = Font.caption
  static let caption2 = Font.caption2

  // MARK: - Line Heights
  static let lineHeightMultiplier: CGFloat = 1.4
}

// MARK: - Typography View Modifiers
extension View {
  func typography(_ style: TypographyStyle) -> some View {
    switch style {
    case .largeTitle:
      return self.font(Typography.largeTitle)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .title:
      return self.font(Typography.title)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .title2:
      return self.font(Typography.title2)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .title3:
      return self.font(Typography.title3)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .headline:
      return self.font(Typography.headline)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .subheadline:
      return self.font(Typography.subheadline)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .body:
      return self.font(Typography.body)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .bodyEmphasized:
      return self.font(Typography.bodyEmphasized)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .callout:
      return self.font(Typography.callout)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .calloutEmphasized:
      return self.font(Typography.calloutEmphasized)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .footnote:
      return self.font(Typography.footnote)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .caption:
      return self.font(Typography.caption)
        .lineSpacing(Typography.lineHeightMultiplier)
    case .caption2:
      return self.font(Typography.caption2)
        .lineSpacing(Typography.lineHeightMultiplier)
    }
  }
}

// MARK: - Typography Styles Enum
enum TypographyStyle {
  case largeTitle
  case title
  case title2
  case title3
  case headline
  case subheadline
  case body
  case bodyEmphasized
  case callout
  case calloutEmphasized
  case footnote
  case caption
  case caption2
}
