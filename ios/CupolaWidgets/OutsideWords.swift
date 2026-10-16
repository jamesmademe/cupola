/// The only words the widgets write themselves. Every other word on a widget
/// is in the snapshot, written by Dart (`outside_snapshot.dart`): a second copy
/// of the app's words in Swift would drift from the first within a release.
///
/// What is here is what exists before the app has said anything: the widgets'
/// names and what each one is for (the gallery shows them before one is
/// added), and the two sentences for a widget that has nothing to draw.
enum OutsideWords {
  static let comingUpName = "Coming up"
  static let downloadsName = "Downloads"
  static let requestsName = "Your requests"

  static let comingUpDescription = "What airs and comes out next."
  static let downloadsDescription = "What is moving, and what is stuck."
  static let requestsDescription = "What you asked for, and when it is ready."

  /// No file yet: the app has not run since the widget was added.
  static let noFile = "Open Cupola to fill this in."

  /// A file, but nothing in it for this widget: a requester has no calendar
  /// and no queue, an operator has no requests of his own, and a calendar no
  /// one set up has nothing to come. No «yet»: for most of them nothing ever
  /// will.
  static let kindAbsent = "Nothing to show here."
}
