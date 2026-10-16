import SwiftUI
import WidgetKit

/// The sizes the widgets are drawn with that are neither a token nor a type
/// role. Everything else (spacing, radii, colours, type) is `OutsideStyle`.
enum OutsideMetrics {
  /// A bar is 4pt tall and fully rounded, as the app's progress tracks are.
  static let barHeight: CGFloat = 4

  /// The poster beside a row in Your requests, 2:3 as every poster.
  static let tinyPoster = CGSize(width: 20, height: 30)

  /// The column of day names in Coming up's rows (`Tomorrow`, `Wednesday`), so
  /// that the titles beside it line up, from the approved board.
  static let dayColumn: CGFloat = 78

  /// Rows that fit a medium widget under its header and beside its lead.
  static let comingRows = 2
  static let downloadRows = 3
  static let requestRows = 3

  /// A 2:3 poster that is [height] tall.
  static func poster(height: CGFloat) -> CGSize {
    CGSize(width: height * 2 / 3, height: height)
  }
}

extension Image {
  /// Tinted rendering takes colour out of every image and tints what is left.
  /// A poster that stays a picture, only desaturated, is still the poster;
  /// iOS 17 has no such mode and tints it, as the system always did.
  @ViewBuilder func outsideDesaturated() -> some View {
    if #available(iOS 18.0, *) {
      widgetAccentedRenderingMode(.desaturated)
    } else {
      self
    }
  }
}

/// A picture over a small widget's whole face. The scrim that makes the words
/// over it legible is not here but behind the words (`OutsideScrim`), so that it
/// covers the text block whatever its height.
struct OutsideArt: View {
  let image: CGImage

  var body: some View {
    GeometryReader { area in
      Image(decorative: image, scale: 1)
        .resizable()
        .scaledToFill()
        .frame(width: area.size.width, height: area.size.height)
        .clipped()
    }
  }
}

/// The scrim behind the words over artwork: full strength under the whole text
/// block and a margin above it, then a ramp to clear, from the block's own top
/// and not from a fixed fraction of the widget. A title that takes two lines
/// grows the block upward, and the scrim goes up with it: the first line of
/// the block is never on bare artwork. Drawn as a `background` of the block,
/// bleeding to the widget's edges through the plate's own padding.
struct OutsideScrim: View {
  /// Full strength above the block, so its first line has margin.
  private static let margin: CGFloat = 12
  /// From clear to full strength, above the margin.
  private static let ramp: CGFloat = 48

  var body: some View {
    let bleed = OutsideStyle.spaceSlabY
    ZStack(alignment: .top) {
      OutsideStyle.scrimFoot
        .padding(.top, -Self.margin).padding(.horizontal, -bleed).padding(.bottom, -bleed)
      LinearGradient(
        colors: [OutsideStyle.scrimClear, OutsideStyle.scrimFoot],
        startPoint: .top, endPoint: .bottom
      )
      .frame(height: Self.ramp)
      .padding(.horizontal, -bleed)
      .offset(y: -(Self.margin + Self.ramp))
    }
  }
}

/// A poster at [size], or the empty track where there is none, so that the
/// rows beside it stay where they are.
struct OutsidePoster: View {
  let image: CGImage?
  let size: CGSize
  let radius: CGFloat
  let palette: OutsidePalette

  var body: some View {
    ZStack {
      if let image {
        Image(decorative: image, scale: 1)
          .resizable()
          .outsideDesaturated()
          .scaledToFill()
      } else {
        palette.track
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }
}

/// How far a thing got: the track, and the fill in its tone or the ink.
struct OutsideBar: View {
  let progress: Double
  let fill: Color
  let track: Color
  @Environment(\.redactionReasons) private var redaction

  var body: some View {
    GeometryReader { area in
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        // A placeholder shows where a bar goes, not how far one got.
        if !redaction.contains(.placeholder) {
          Capsule().fill(fill).frame(width: area.size.width * min(max(progress, 0), 1))
        }
      }
    }
    .frame(height: OutsideMetrics.barHeight)
  }
}

/// A place a tap on this part opens (a medium widget's rows). Where there is
/// none, the part is only drawn, and the tap falls to the widget's own link.
struct OutsideLinked<Content: View>: View {
  let route: String?
  @ViewBuilder let content: Content

  var body: some View {
    if let url = OutsideLink.url(for: route) {
      Link(destination: url) { content }
    } else {
      content
    }
  }
}

/// [text] with its spaces made non-breaking inside each part between ` · `
/// separators, so that a line breaks only at a separator and never inside a
/// part (`2.4 MB/s`, `As of 14:02`). The separators keep their ordinary spaces.
func outsideBreakable(_ text: String) -> String {
  text.components(separatedBy: " \u{00B7} ")
    .map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
    .joined(separator: " \u{00B7} ")
}

/// A medium widget's first line: what it is on the left, how old it is on the
/// right. The age is never truncated; the name gives way to it.
struct OutsideHeader: View {
  let leading: String
  let trailing: String
  let palette: OutsidePalette

  var body: some View {
    HStack(spacing: OutsideStyle.spaceSm) {
      Text(outsideBreakable(leading)).outsideType(.label).foregroundStyle(palette.dim)
      Spacer(minLength: 0)
      Text(outsideBreakable(trailing)).outsideType(.label).foregroundStyle(palette.dim)
        .fixedSize(horizontal: true, vertical: false)
    }
  }
}

/// A medium list widget: its header, and what it lists directly under it,
/// top-aligned, with the spare room at the foot. (Coming up's medium is not
/// one: its lead is at the top and its rows at the foot, as the board has it.)
struct OutsideMediumList<Content: View>: View {
  let leading: String
  let face: OutsideFace
  let palette: OutsidePalette
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      OutsideHeader(leading: leading, trailing: face.age, palette: palette)
      content.padding(.top, OutsideStyle.spaceRow)
      Spacer(minLength: 0)
    }
    .outsidePlate()
  }
}

/// A line that says only how old the drawing is.
struct OutsideAge: View {
  let age: String
  let palette: OutsidePalette

  var body: some View {
    Text(age).outsideType(.line).foregroundStyle(palette.dim)
  }
}

/// A widget's face when it has nothing to lead with: its name above, what it
/// says of that below. A medium one has a header, as the others do, and so
/// always says its age.
struct OutsideCalm: View {
  let face: OutsideFace
  let palette: OutsidePalette
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if family == .systemMedium {
      OutsideMediumList(leading: face.title, face: face, palette: palette) { calm }
    } else {
      VStack(alignment: .leading, spacing: OutsideStyle.spaceSm) {
        Text(face.title).outsideType(.label).foregroundStyle(palette.dim)
        Spacer(minLength: 0)
        calm
        if face.aged { OutsideAge(age: face.age, palette: palette) }
      }
      .outsidePlate()
    }
  }

  @ViewBuilder private var calm: some View {
    if let calm = face.calm {
      Text(calm).outsideType(.title, lines: 3).foregroundStyle(palette.ink)
    }
  }
}

/// One thing in a small widget on its ground: its title, its bar when it has
/// one, and a last line that is its words in their tone, or the age where the
/// drawing is old enough to say so.
struct OutsideItemBlock: View {
  let item: OutsideItem
  let face: OutsideFace
  let palette: OutsidePalette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(item.title).outsideType(.title).foregroundStyle(palette.ink).outsidePrivate()
      if let progress = item.progress {
        OutsideBar(progress: progress, fill: palette.tone(item.tone), track: palette.track)
          .padding(.top, OutsideStyle.spaceXs)
      }
      if face.aged {
        OutsideAge(age: face.age, palette: palette).padding(.top, OutsideStyle.spaceXs)
      } else if let words = item.words {
        Text(words).outsideType(.line).foregroundStyle(palette.tone(item.tone))
          .padding(.top, OutsideStyle.spaceXs)
      }
    }
  }
}

/// A small widget's lead at the foot of its plate: an eyebrow, a title (two
/// lines before it truncates, since the picture behind it has room), and what
/// it says. Over artwork the words are the artwork's (`onArt`, the same in both
/// rooms), and a tone is the dark room's, since the scrim is its ground; on
/// the ground they are the room's. Where the drawing is old enough to say so,
/// the age takes the place of the last line. Without artwork it names the
/// widget at the top, as the other small widgets do ([showsName]).
struct OutsideLeadPlate: View {
  let face: OutsideFace
  let lead: OutsideItem
  /// Which part of the lead the tone belongs to: Coming up's is its words'
  /// state, Your requests' is the eyebrow's (`Ready to watch`, green).
  let eyebrowTone: OutsideTone?
  let wordsTone: OutsideTone?
  let onArt: Bool
  let showsName: Bool
  let palette: OutsidePalette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsName {
        Text(face.title).outsideType(.label).foregroundStyle(palette.dim)
      }
      Spacer(minLength: 0)
      VStack(alignment: .leading, spacing: OutsideStyle.spaceXxs) {
        if let eyebrow = lead.eyebrow {
          Text(eyebrow).outsideType(.label).foregroundStyle(eyebrowColor)
        }
        Text(lead.title).outsideType(.title, lines: 2).foregroundStyle(titleColor)
          .outsidePrivate()
        if face.aged {
          Text(face.age).outsideType(.data).foregroundStyle(wordsColor(tone: nil))
        } else if let words = lead.words {
          Text(words).outsideType(.data).foregroundStyle(wordsColor(tone: wordsTone))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background { if onArt { OutsideScrim() } }
    }
    .outsidePlate()
  }

  private var eyebrowColor: Color {
    if onArt {
      return eyebrowTone.map { OutsideRoom.dark.tone($0) } ?? OutsideStyle.onArtDim
    }
    return palette.tone(eyebrowTone, or: palette.dim)
  }

  private var titleColor: Color { onArt ? OutsideStyle.onArt : palette.ink }

  private func wordsColor(tone: OutsideTone?) -> Color {
    onArt ? OutsideStyle.onArtDim : palette.tone(tone, or: palette.dim)
  }
}

private struct OutsidePrivateTitle: ViewModifier {
  @Environment(\.redactionReasons) private var redaction

  func body(content: Content) -> some View {
    // A title is private: the system hides it on a locked phone and in
    // StandBy when the person asked it to. The placeholder is not a title, and
    // `privacySensitive` would draw its stand-in text unredacted.
    if redaction.contains(.placeholder) {
      content
    } else {
      content.privacySensitive()
    }
  }
}

extension View {
  /// Marks a title as private (`privacySensitive`), except while the widget is
  /// only the shape of a drawing.
  func outsidePrivate() -> some View {
    modifier(OutsidePrivateTitle())
  }

  /// A small or medium widget's own padding. The widgets turn the system's
  /// margins off (`contentMarginsDisabled`) so that an artwork plate can run
  /// to the edge, and so every widget pads itself the same.
  func outsidePlate() -> some View {
    padding(OutsideStyle.spaceSlabY)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
