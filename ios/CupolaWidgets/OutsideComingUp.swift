import SwiftUI
import WidgetKit

/// Coming up: what airs and comes out next.
///
/// Small leads with the next title over its own artwork. Medium puts the
/// lead's poster at the left, its words beside it, and the next two things
/// under them. The face says which is the lead and which are the rest.
struct OutsideComingUp: View {
  let face: OutsideFace
  let pictures: [String: CGImage]
  /// The artwork a small widget is drawn over; nil draws it on its ground.
  let art: CGImage?
  let palette: OutsidePalette
  @Environment(\.widgetFamily) private var family
  @ScaledMetric(relativeTo: .footnote) private var dayColumn = OutsideMetrics.dayColumn

  var body: some View {
    if face.lead == nil {
      OutsideCalm(face: face, palette: palette)
    } else if family == .systemMedium {
      medium
    } else {
      small
    }
  }

  @ViewBuilder private var small: some View {
    if let lead = face.lead {
      OutsideLeadPlate(
        face: face, lead: lead, eyebrowTone: nil, wordsTone: lead.tone,
        onArt: art != nil, showsName: art == nil, palette: palette)
    }
  }

  @ViewBuilder private var medium: some View {
    if let lead = face.lead {
      GeometryReader { area in
        let inner = max(0, area.size.height - 2 * OutsideStyle.spaceSlabY)
        HStack(alignment: .top, spacing: OutsideStyle.spaceSlabY) {
          if let name = lead.poster, let image = pictures[name] {
            OutsidePoster(
              image: image, size: OutsideMetrics.poster(height: inner),
              radius: OutsideStyle.posterRadius, palette: palette)
          }
          VStack(alignment: .leading, spacing: 0) {
            // The eyebrow says when, and the age says how fresh: the one line
            // the other mediums give to their header.
            OutsideHeader(leading: lead.eyebrow ?? "", trailing: face.age, palette: palette)
            Text(lead.title).outsideType(.title, lines: 2).foregroundStyle(palette.ink)
              .outsidePrivate()
              .padding(.top, OutsideStyle.spaceXxs)
            if let words = lead.words {
              Text(words).outsideType(.line).foregroundStyle(palette.tone(lead.tone, or: palette.dim))
            }
            Spacer(minLength: OutsideStyle.spaceS)
            VStack(alignment: .leading, spacing: OutsideStyle.spaceS) {
              ForEach(Array(face.items.prefix(OutsideMetrics.comingRows).enumerated()), id: \.offset) {
                _, item in
                OutsideLinked(route: item.route) { row(item) }
              }
            }
          }
        }
        .padding(OutsideStyle.spaceSlabY)
        .frame(width: area.size.width, height: area.size.height, alignment: .topLeading)
      }
    }
  }

  /// `Tomorrow  Sprite Fright  S1 E3`: the day in its column, the title, and
  /// the rest right-aligned. The title is what gives way: the words never
  /// truncate before it does.
  private func row(_ item: OutsideItem) -> some View {
    HStack(spacing: OutsideStyle.spaceS) {
      if let day = item.eyebrow {
        Text(day).outsideType(.line).foregroundStyle(palette.dim)
          .frame(width: dayColumn, alignment: .leading)
      }
      Text(item.title).outsideType(.line).foregroundStyle(palette.ink).outsidePrivate()
      Spacer(minLength: 0)
      if let words = item.words {
        Text(words).outsideType(.data).foregroundStyle(palette.tone(item.tone, or: palette.dim))
          .fixedSize(horizontal: true, vertical: false)
      }
    }
  }
}
