import SwiftUI
import WidgetKit

/// Cupola's widgets (`OutsideKind`): what the app shows outside itself, drawn
/// from the file it writes (`OutsideShelf`). Which of them a person can add is
/// not decided here: an operator has a calendar and a queue, a requester has
/// her requests, and a widget with nothing for her says so (`OutsideWords`).
@main
struct CupolaWidgets: WidgetBundle {
  var body: some Widget {
    OutsideComingUpWidget()
    OutsideDownloadsWidget()
    OutsideRequestsWidget()
  }
}
