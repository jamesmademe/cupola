import SwiftUI
import UIKit
import WidgetKit

/// The widgets Cupola has. The raw value is both the widget's `kind` and its
/// key in the snapshot: `OutsideWidget`'s names in
/// `lib/features/outside/domain/outside_snapshot.dart`.
enum OutsideKind: String, CaseIterable {
  case comingUp, downloads, requests

  var name: String {
    switch self {
    case .comingUp: return OutsideWords.comingUpName
    case .downloads: return OutsideWords.downloadsName
    case .requests: return OutsideWords.requestsName
    }
  }

  var summary: String {
    switch self {
    case .comingUp: return OutsideWords.comingUpDescription
    case .downloads: return OutsideWords.downloadsDescription
    case .requests: return OutsideWords.requestsDescription
    }
  }

  var families: [WidgetFamily] {
    switch self {
    case .comingUp, .requests: return [.systemSmall, .systemMedium]
    case .downloads: return [.systemSmall, .systemMedium, .accessoryRectangular]
    }
  }
}

/// What a widget has to draw at one moment.
enum OutsideContent {
  /// The shape of a drawing, redacted: the system's placeholder and the
  /// gallery before the app has ever written a file. Never invented words.
  case placeholder
  /// The app has not written a file (or not one this code reads).
  case noFile
  /// A file, with nothing in it for this widget.
  case absent
  /// A frame of the snapshot and the pictures it names, already decoded.
  case face(OutsideFace, pictures: [String: CGImage])
}

struct OutsideEntry: TimelineEntry {
  let date: Date
  let content: OutsideContent
}

/// One provider for the three widgets: they differ in what they draw and in
/// which pictures they need, not in how a snapshot becomes a timeline.
///
/// The snapshot's frames are already the drawings, each valid from an instant
/// (`OutsideFrame`), so the timeline is the frames: the one whose time has
/// come, dated now, and each later one at its own instant. The policy is
/// `.never` because the data only changes when the app runs, and the app asks
/// for a reload after each run.
struct OutsideProvider: TimelineProvider {
  let kind: OutsideKind

  func placeholder(in context: Context) -> OutsideEntry {
    OutsideEntry(date: .now, content: .placeholder)
  }

  func getSnapshot(in context: Context, completion: @escaping (OutsideEntry) -> Void) {
    let first = entries(in: context)[0]
    // The gallery shows a widget before the app has run: its layout, redacted,
    // rather than a sentence addressed to someone who has not added it yet.
    if context.isPreview, case .noFile = first.content {
      completion(placeholder(in: context))
    } else {
      completion(first)
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<OutsideEntry>) -> Void) {
    completion(Timeline(entries: entries(in: context), policy: .never))
  }

  /// Never empty.
  private func entries(in context: Context, now: Date = .now) -> [OutsideEntry] {
    guard let snapshot = OutsideShelf.read() else {
      return [OutsideEntry(date: now, content: .noFile)]
    }
    let frames = (snapshot.widgets[kind.rawValue] ?? []).sorted { $0.from < $1.from }
    guard !frames.isEmpty else {
      return [OutsideEntry(date: now, content: .absent)]
    }
    // The last frame whose time has come; a file whose first frame is still
    // ahead (the clock was set back) draws that one rather than nothing.
    let current = frames.lastIndex { $0.from <= now } ?? 0
    var decoded: [String: CGImage?] = [:]
    func entry(_ frame: OutsideFrame, at date: Date) -> OutsideEntry {
      OutsideEntry(
        date: date,
        content: .face(
          frame.face, pictures: pictures(for: frame.face, in: context, decoded: &decoded)))
    }
    return [entry(frames[current], at: now)]
      + frames[(current + 1)...].map { entry($0, at: $0.from) }
  }

  /// The pictures this widget draws in this size, each decoded once however
  /// many frames name it, and no larger than it is drawn.
  private func pictures(
    for face: OutsideFace, in context: Context, decoded: inout [String: CGImage?]
  ) -> [String: CGImage] {
    let area = context.displaySize
    // What each size draws: the candidates in order of preference, and whether
    // it draws the first that decodes or all of them.
    var candidates: [(name: String, size: CGSize)] = []
    var all = false
    switch (kind, context.family) {
    case (.comingUp, .systemSmall), (.requests, .systemSmall):
      // The art plate: the backdrop, else the poster, over the whole widget.
      candidates = [face.lead?.backdrop, face.lead?.poster].compactMap { $0 }.map { ($0, area) }
    case (.comingUp, .systemMedium):
      let inner = max(0, area.height - 2 * OutsideStyle.spaceSlabY)
      candidates = [face.lead?.poster].compactMap { $0 }
        .map { ($0, OutsideMetrics.poster(height: inner)) }
    case (.requests, .systemMedium):
      candidates = face.requestRows.compactMap { $0.poster }.map { ($0, OutsideMetrics.tinyPoster) }
      all = true
    default:
      break
    }

    var pictures: [String: CGImage] = [:]
    for (name, size) in candidates {
      let image: CGImage?
      if let hit = decoded[name] {
        image = hit
      } else {
        image = OutsideShelf.picture(named: name, covering: size)
        decoded[name] = .some(image)
      }
      guard let image else { continue }
      pictures[name] = image
      if !all { break }
    }
    return pictures
  }
}

extension OutsideFace {
  /// A drawing with every part present, for the placeholder: the system draws
  /// it redacted, so what is written here is never read, only measured. It is
  /// not a sentence and must never become one.
  static let shape: OutsideFace = {
    func blocks(_ count: Int) -> String { String(repeating: "x", count: count) }
    func item(progress: Double? = nil) -> OutsideItem {
      OutsideItem(
        title: blocks(14), eyebrow: blocks(12), words: blocks(10), tone: nil,
        progress: progress, poster: nil, backdrop: nil, route: nil)
    }
    return OutsideFace(
      title: blocks(10), subtitle: blocks(24), figure: blocks(2), figureWords: blocks(6),
      lead: item(progress: 0.5), items: [item(progress: 0.5), item(progress: 0.5), item(progress: 0.5)],
      calm: nil, age: blocks(11), aged: false, route: nil)
  }()
}
