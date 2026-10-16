import SwiftUI
import WidgetKit

/// The colours of one room, as the app paints them (`OutsideStyle.swift`
/// holds the two instances, generated from the live theme).
struct OutsideRoom {
  let ground: Color
  let ink: Color
  let dim: Color
  /// The empty part of a bar: the ink at 12%.
  let track: Color
  let green: Color
  let amber: Color
  let blue: Color
  let neutral: Color

  /// A tone by name. Red is not a widget's tone: a server out of reach is
  /// where the phone is, not a fact about the server.
  func tone(_ tone: OutsideTone) -> Color {
    switch tone {
    case .green: return green
    case .amber: return amber
    case .blue: return blue
    case .neutral: return neutral
    }
  }
}

/// What a widget paints with, for the room and the way the system renders it.
///
/// In full colour that is the app's own palette. Tinted, clear and the lock
/// screen (`accented`, `vibrant`) take every colour away and tint the rest
/// themselves, so there is no ground to draw and a tone cannot be told by its
/// hue: the words carry it, and the ink and the dim ink are the system's
/// primary and secondary, which stay legible whatever the tint is.
struct OutsidePalette {
  let room: OutsideRoom
  let fullColor: Bool

  init(colorScheme: ColorScheme, renderingMode: WidgetRenderingMode) {
    room = colorScheme == .dark ? .dark : .light
    fullColor = renderingMode == .fullColor
  }

  var ground: Color { fullColor ? room.ground : .clear }
  var ink: Color { fullColor ? room.ink : .primary }
  var dim: Color { fullColor ? room.dim : .secondary }
  var track: Color { fullColor ? room.track : Color.primary.opacity(0.25) }

  /// [tone]'s colour; null is the ink, or [fallback] where a word that has no
  /// tone is not the ink (a line that only says where it stands is dim).
  func tone(_ tone: OutsideTone?, or fallback: Color? = nil) -> Color {
    guard let tone else { return fallback ?? ink }
    guard fullColor else { return tone == .neutral ? dim : ink }
    return room.tone(tone)
  }
}
