import Foundation


enum HeatmapDisplayMode: String, CaseIterable, Codable {
  case quantity = "quantity"
  case valueSum = "valueSum"

  var localizedTitle: String {
    switch self {
    case .quantity: return appLocalizedString(Localizable.quantity)
    case .valueSum: return appLocalizedString(Localizable.values)
    }
  }
}
