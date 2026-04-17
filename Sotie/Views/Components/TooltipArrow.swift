import SwiftUI

/// Reusable triangle arrow for tooltips.
/// Points in the specified direction, sized by the frame applied to it.
struct TooltipArrow: Shape {
  enum Direction {
    case up, down, left, right
  }

  let direction: Direction

  func path(in rect: CGRect) -> Path {
    var path = Path()

    switch direction {
    case .up:
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    case .down:
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    case .left:
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    case .right:
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    }

    path.closeSubpath()
    return path
  }
}
