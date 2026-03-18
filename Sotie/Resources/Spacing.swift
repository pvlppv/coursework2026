import Foundation

// MARK: - Spacing System
struct Spacing {

  // MARK: - Basic Spacing
  static let xxSmall: CGFloat = 4
  static let xSmall: CGFloat = 8
  static let small: CGFloat = 12
  static let medium: CGFloat = 16
  static let large: CGFloat = 24
  static let xLarge: CGFloat = 32
  static let xxLarge: CGFloat = 48

  // MARK: - Corner Radius - Increased roundness for softer aesthetic
  static let cornerRadiusSmall: CGFloat = 16
  static let cornerRadiusMedium: CGFloat = 20
  static let cornerRadiusLarge: CGFloat = 24
  static let cornerRadiusXLarge: CGFloat = 32

  // MARK: - Common Layout Values
  static let screenPadding: CGFloat = medium
  static let cardPadding: CGFloat = medium
  static let buttonHeight: CGFloat = 48
  static let iconSize: CGFloat = 24
  static let iconSizeSmall: CGFloat = 16
  static let iconSizeLarge: CGFloat = 32

  // MARK: - Shadow Values
  static let shadowRadius: CGFloat = 8
  static let shadowOffset: CGFloat = 2
  static let shadowOpacity: Double = 0.1
}
