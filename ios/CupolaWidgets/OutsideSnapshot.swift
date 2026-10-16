import Foundation

/// The file the app writes for the widgets, as Swift reads it: a mirror of
/// `OutsideSnapshot.toJson()` and the types under it
/// (`lib/features/outside/domain/outside_snapshot.dart`). Dart writes every
/// word and the widget only draws the frame whose time has come, so nothing
/// here derives a word, a figure or a time: a key the file does not have is a
/// nil here, never a default.

/// The tone of a word or a bar, by name. Red is never one: a widget does not
/// draw it.
enum OutsideTone: String, Decodable {
  case green, amber, blue, neutral
}

/// One thing in a widget: a title to come, a download, a request.
struct OutsideItem: Equatable {
  let title: String
  let eyebrow: String?
  let words: String?
  let tone: OutsideTone?
  /// How far it got, 0 to 1; nil draws no bar.
  let progress: Double?
  /// File names in `outside_pictures/`.
  let poster: String?
  let backdrop: String?
  /// A location of the app's router (`OutsideLink`).
  let route: String?
}

/// What one widget draws at one moment, in every size.
struct OutsideFace: Equatable, Decodable {
  let title: String
  let subtitle: String?
  let figure: String?
  let figureWords: String?
  let lead: OutsideItem?
  let items: [OutsideItem]
  let calm: String?
  /// `As of 14:02`.
  let age: String
  /// Old enough that the small widget gives a line to its age.
  let aged: Bool
  let route: String?
}

/// A face and the instant from which it is the true one.
struct OutsideFrame {
  let from: Date
  let face: OutsideFace
}

struct OutsideSnapshot {
  /// The shape of the file this code reads. Any other reads as no snapshot:
  /// a widget draws nothing rather than misread a file it does not know.
  static let version = 1

  let takenAt: Date
  let audience: String
  /// Each widget's frames, by `OutsideKind.rawValue`; a widget this person has
  /// nothing for is absent.
  let widgets: [String: [OutsideFrame]]
}

// MARK: - Decoding

extension OutsideItem: Decodable {
  private enum Key: String, CodingKey {
    case title, eyebrow, words, tone, progress, poster, backdrop, route
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Key.self)
    title = try c.decode(String.self, forKey: .title)
    eyebrow = try c.decodeIfPresent(String.self, forKey: .eyebrow)
    words = try c.decodeIfPresent(String.self, forKey: .words)
    // A tone this code does not know is the ink, not a file nobody can read.
    tone = (try? c.decodeIfPresent(OutsideTone.self, forKey: .tone)) ?? nil
    progress = try c.decodeIfPresent(Double.self, forKey: .progress)
    poster = try c.decodeIfPresent(String.self, forKey: .poster)
    backdrop = try c.decodeIfPresent(String.self, forKey: .backdrop)
    route = try c.decodeIfPresent(String.self, forKey: .route)
  }
}

extension OutsideFrame: Decodable {
  private enum Key: String, CodingKey { case from, face }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Key.self)
    let stamp = try c.decode(String.self, forKey: .from)
    guard let date = OutsideDate.parse(stamp) else {
      throw DecodingError.dataCorruptedError(
        forKey: .from, in: c, debugDescription: "not an ISO 8601 instant")
    }
    from = date
    face = try c.decode(OutsideFace.self, forKey: .face)
  }
}

extension OutsideSnapshot: Decodable {
  private enum Key: String, CodingKey { case version, takenAt, audience, widgets }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Key.self)
    guard try c.decode(Int.self, forKey: .version) == Self.version else {
      throw DecodingError.dataCorruptedError(
        forKey: .version, in: c, debugDescription: "another version of the file")
    }
    let stamp = try c.decode(String.self, forKey: .takenAt)
    guard let date = OutsideDate.parse(stamp) else {
      throw DecodingError.dataCorruptedError(
        forKey: .takenAt, in: c, debugDescription: "not an ISO 8601 instant")
    }
    takenAt = date
    audience = try c.decode(String.self, forKey: .audience)
    widgets = try c.decode([String: [OutsideFrame]].self, forKey: .widgets)
  }
}

// MARK: - Dates

/// The instants Dart writes: `DateTime.toUtc().toIso8601String()`, which is
/// `2026-10-16T14:02:00.000Z` for a whole millisecond and
/// `2026-10-16T14:02:00.123456Z` otherwise, up to six fractional digits.
/// `ISO8601DateFormatter` keeps a fraction only to the millisecond, and with
/// its fractional option on it refuses a date that has none, so the fraction
/// is cut off, parsed as a number and added back: no digit count, and no
/// whole second, makes a frame vanish.
enum OutsideDate {
  private static let formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  static func parse(_ text: String) -> Date? {
    guard let dot = text.firstIndex(of: ".") else { return formatter.date(from: text) }
    let afterDot = text[text.index(after: dot)...]
    let digits = afterDot.prefix { $0 >= "0" && $0 <= "9" }
    guard !digits.isEmpty, let fraction = Double("0." + digits) else { return nil }
    let whole = String(text[..<dot]) + afterDot.dropFirst(digits.count)
    return formatter.date(from: whole)?.addingTimeInterval(fraction)
  }
}
