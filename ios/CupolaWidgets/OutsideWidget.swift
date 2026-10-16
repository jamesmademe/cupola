import SwiftUI
import WidgetKit

/// The three widgets share how a snapshot becomes a timeline and how an empty
/// one reads, and differ in the drawing (`OutsideComingUp`, `OutsideDownloads`,
/// `OutsideRequests`) and in the sizes they offer, so one configuration serves
/// them all and each `Widget` below only names its kind (a `Widget` takes no
/// parameter: the system makes it with `init()`).
extension OutsideKind {
  func configuration() -> some WidgetConfiguration {
    StaticConfiguration(kind: rawValue, provider: OutsideProvider(kind: self)) { entry in
      OutsideRoot(kind: self, entry: entry)
    }
    .configurationDisplayName(name)
    .description(summary)
    .supportedFamilies(families)
    // The system's margins are off so that a small widget's artwork can run to
    // the edge; every drawing pads itself (`outsidePlate`).
    .contentMarginsDisabled()
  }
}

struct OutsideComingUpWidget: Widget {
  var body: some WidgetConfiguration { OutsideKind.comingUp.configuration() }
}

struct OutsideDownloadsWidget: Widget {
  var body: some WidgetConfiguration { OutsideKind.downloads.configuration() }
}

struct OutsideRequestsWidget: Widget {
  var body: some WidgetConfiguration { OutsideKind.requests.configuration() }
}

/// The room a widget is drawn in and the artwork it takes, from the three
/// things the system tells it: the colour scheme, the way it renders (full
/// colour, tinted, the lock screen) and the size.
struct OutsideLook {
  let palette: OutsidePalette
  /// The artwork a small widget is drawn over: only in full colour (tinted and
  /// clear rendering drop it), and only where the lead has a picture that
  /// decoded: the backdrop first, else the poster.
  let art: CGImage?

  init(
    kind: OutsideKind, entry: OutsideEntry, colorScheme: ColorScheme,
    renderingMode: WidgetRenderingMode, family: WidgetFamily
  ) {
    palette = OutsidePalette(colorScheme: colorScheme, renderingMode: renderingMode)
    if palette.fullColor, family == .systemSmall, kind != .downloads,
      case .face(let face, let pictures) = entry.content, let lead = face.lead
    {
      art = [lead.backdrop, lead.poster].compactMap { $0 }.lazy.compactMap { pictures[$0] }.first
    } else {
      art = nil
    }
  }
}

/// What every widget is wrapped in: the ground or the artwork under it, which
/// the system draws in its own layer (`containerBackground`), and the drawing
/// over it.
struct OutsideRoot: View {
  let kind: OutsideKind
  let entry: OutsideEntry

  var body: some View {
    OutsideScene(kind: kind, entry: entry)
      .containerBackground(for: .widget) { OutsideBackdrop(kind: kind, entry: entry) }
  }
}

struct OutsideBackdrop: View {
  let kind: OutsideKind
  let entry: OutsideEntry
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let look = OutsideLook(
      kind: kind, entry: entry, colorScheme: colorScheme, renderingMode: renderingMode,
      family: family)
    if let art = look.art {
      OutsideArt(image: art)
    } else {
      look.palette.ground
    }
  }
}

/// The drawing: its room, its Dynamic Type ceiling and the link a tap on it
/// follows.
struct OutsideScene: View {
  let kind: OutsideKind
  let entry: OutsideEntry
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let look = OutsideLook(
      kind: kind, entry: entry, colorScheme: colorScheme, renderingMode: renderingMode,
      family: family)
    content(palette: look.palette, art: look.art)
      // Type grows with the system's setting up to here: a widget does not
      // scroll, and past this its words would push each other out.
      .dynamicTypeSize(...DynamicTypeSize.xLarge)
      .widgetURL(link)
  }

  @ViewBuilder
  private func content(palette: OutsidePalette, art: CGImage?) -> some View {
    switch entry.content {
    case .placeholder:
      faceView(.shape, pictures: [:], art: nil, palette: palette)
        .redacted(reason: .placeholder)
    case .noFile:
      empty(OutsideWords.noFile, palette: palette)
    case .absent:
      empty(OutsideWords.kindAbsent, palette: palette)
    case .face(let face, let pictures):
      faceView(face, pictures: pictures, art: art, palette: palette)
    }
  }

  @ViewBuilder
  private func faceView(
    _ face: OutsideFace, pictures: [String: CGImage], art: CGImage?, palette: OutsidePalette
  ) -> some View {
    switch kind {
    case .comingUp:
      OutsideComingUp(face: face, pictures: pictures, art: art, palette: palette)
    case .downloads:
      OutsideDownloads(face: face, palette: palette)
    case .requests:
      OutsideRequests(face: face, pictures: pictures, art: art, palette: palette)
    }
  }

  /// A widget with nothing to draw: its name and one line.
  private func empty(_ line: String, palette: OutsidePalette) -> some View {
    VStack(alignment: .leading, spacing: OutsideStyle.spaceXxs) {
      Text(kind.name).outsideType(.title).foregroundStyle(palette.ink)
      Text(line).outsideType(.line, lines: 3).foregroundStyle(palette.dim)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(family == .accessoryRectangular ? 0 : OutsideStyle.spaceSlabY)
  }

  /// Where a tap on the widget, away from its rows, opens.
  private var link: URL? {
    guard case .face(let face, _) = entry.content else { return nil }
    return OutsideLink.url(for: face.route)
  }
}
