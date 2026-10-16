import SwiftUI
import WidgetKit

/// Downloads: what is moving, and what is stuck.
///
/// Small is the one figure, what leads under it, and where it stands. Medium
/// is the rows, each with its bar. The lock screen's rectangle is two lines of
/// words in the system's tint: a figure's tone, or a bar, is not drawn there.
///
/// A calm face (`calm` is set: nothing is downloading) says it once, in its
/// calm line, and never draws its subtitle, which would say it again.
struct OutsideDownloads: View {
  let face: OutsideFace
  let palette: OutsidePalette
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .systemMedium: medium
    case .accessoryRectangular: rectangular
    default: small
    }
  }

  /// The module's line, unless the face is calm.
  private var subtitle: String? { face.calm == nil ? face.subtitle : nil }

  // MARK: Small

  private var small: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(face.title).outsideType(.label).foregroundStyle(palette.dim)
      Spacer(minLength: OutsideStyle.spaceSm)
      if let figure = face.figure {
        HStack(alignment: .firstTextBaseline, spacing: OutsideStyle.spaceSm) {
          Text(figure).outsideType(.figureHero).foregroundStyle(palette.ink).widgetAccentable()
          if let words = face.figureWords {
            Text(words).outsideType(.figureSmall).foregroundStyle(palette.dim)
          }
        }
      } else if let subtitle {
        Text(subtitle).outsideType(.line, lines: 2).foregroundStyle(palette.dim)
      }
      // What leads is the stuck one, which needs a person; failing that, the
      // first that moves. With neither, the face's own word that it is calm.
      if let item = face.lead ?? face.items.first {
        OutsideItemBlock(item: item, face: face, palette: palette)
          .padding(.top, OutsideStyle.spaceRow)
      } else {
        if let calm = face.calm {
          Text(calm).outsideType(.title, lines: 2).foregroundStyle(palette.ink)
        }
        if face.aged {
          OutsideAge(age: face.age, palette: palette).padding(.top, OutsideStyle.spaceXs)
        }
      }
    }
    .outsidePlate()
  }

  // MARK: Medium

  /// The stuck one first, then the rest. The face lists the stuck ones among
  /// its items as well (the Home's rows do), so the lead is not drawn twice.
  private var rows: [OutsideItem] {
    let rest = face.items.filter { $0 != face.lead }
    return Array(([face.lead].compactMap { $0 } + rest).prefix(OutsideMetrics.downloadRows))
  }

  private var medium: some View {
    OutsideMediumList(leading: subtitle ?? face.title, face: face, palette: palette) {
      if rows.isEmpty {
        if let calm = face.calm {
          Text(calm).outsideType(.title, lines: 2).foregroundStyle(palette.ink)
        }
      } else {
        VStack(alignment: .leading, spacing: OutsideStyle.spaceRow) {
          ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
            OutsideLinked(route: item.route) { row(item) }
          }
        }
      }
    }
  }

  private func row(_ item: OutsideItem) -> some View {
    VStack(alignment: .leading, spacing: OutsideStyle.spaceXs) {
      HStack(spacing: OutsideStyle.spaceSm) {
        Text(item.title).outsideType(.line).foregroundStyle(palette.ink).outsidePrivate()
        Spacer(minLength: 0)
        if let words = item.words {
          Text(words).outsideType(.data).foregroundStyle(palette.tone(item.tone))
            .fixedSize(horizontal: true, vertical: false)
        }
      }
      if let progress = item.progress {
        OutsideBar(progress: progress, fill: palette.tone(item.tone), track: palette.track)
      }
    }
  }

  // MARK: Lock screen

  private var rectangular: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(outsideBreakable(face.title)).outsideType(.label).foregroundStyle(palette.dim)
      if let line = face.calm ?? face.subtitle {
        Text(outsideBreakable(line)).outsideType(.line, lines: 2).foregroundStyle(palette.ink)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
