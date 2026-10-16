import SwiftUI
import WidgetKit

extension OutsideFace {
  /// Medium's rows: the face's own, or its lead as a row when the face has no
  /// others (the Home lists what is ready among its rows; a face that does not
  /// must not draw nothing while it has a lead).
  var requestRows: [OutsideItem] {
    if !items.isEmpty { return Array(items.prefix(OutsideMetrics.requestRows)) }
    guard let lead else { return [] }
    return [
      OutsideItem(
        title: lead.title, eyebrow: nil, words: lead.eyebrow, tone: lead.tone, progress: nil,
        poster: lead.poster, backdrop: nil, route: lead.route)
    ]
  }
}

/// Your requests: what she asked for, and when it is ready. Only hers, in the
/// words the Home gives them, and no service's name.
///
/// Small leads with what is ready to watch over its artwork, as Coming up
/// does; with nothing ready it names itself and gives its first request.
/// Medium is her requests, a tiny poster before each.
struct OutsideRequests: View {
  let face: OutsideFace
  let pictures: [String: CGImage]
  let art: CGImage?
  let palette: OutsidePalette
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if family == .systemMedium {
      medium
    } else {
      small
    }
  }

  // MARK: Small

  @ViewBuilder private var small: some View {
    if let lead = face.lead {
      // Ready to watch is the eyebrow's tone (green); the words are the count
      // of what is still on its way, which has none.
      OutsideLeadPlate(
        face: face, lead: lead, eyebrowTone: lead.tone, wordsTone: nil,
        onArt: art != nil, showsName: art == nil, palette: palette)
    } else if let first = face.items.first {
      VStack(alignment: .leading, spacing: 0) {
        Text(face.title).outsideType(.label).foregroundStyle(palette.dim)
        Spacer(minLength: OutsideStyle.spaceSm)
        OutsideItemBlock(item: first, face: face, palette: palette)
      }
      .outsidePlate()
    } else {
      OutsideCalm(face: face, palette: palette)
    }
  }

  // MARK: Medium

  private var medium: some View {
    OutsideMediumList(leading: face.title, face: face, palette: palette) {
      let rows = face.requestRows
      if rows.isEmpty {
        if let calm = face.calm {
          Text(calm).outsideType(.title, lines: 2).foregroundStyle(palette.ink)
        }
      } else {
        VStack(alignment: .leading, spacing: OutsideStyle.spaceS) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
            OutsideLinked(route: item.route) { row(item) }
          }
        }
      }
    }
  }

  private func row(_ item: OutsideItem) -> some View {
    HStack(spacing: OutsideStyle.spaceRow) {
      OutsidePoster(
        image: item.poster.flatMap { pictures[$0] }, size: OutsideMetrics.tinyPoster,
        radius: OutsideStyle.tinyPosterRadius, palette: palette)
      Text(item.title).outsideType(.line).foregroundStyle(palette.ink).outsidePrivate()
      Spacer(minLength: 0)
      if let words = item.words {
        Text(words).outsideType(.line).foregroundStyle(palette.tone(item.tone))
          .fixedSize(horizontal: true, vertical: false)
      }
    }
  }
}
