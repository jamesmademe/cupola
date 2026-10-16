import CoreText
import SwiftUI
import UIKit

/// One axis of a variable font, by its four-letter tag (`wght`, `wdth`,
/// `opsz`).
struct OutsideAxis {
  let tag: String
  let value: CGFloat

  init(_ tag: String, _ value: CGFloat) {
    self.tag = tag
    self.value = value
  }

  /// The tag as Core Text names an axis: its four bytes as one integer.
  var identifier: Int {
    tag.utf8.reduce(0) { $0 << 8 | Int($1) }
  }
}

/// A type role as the app draws it: what `AppTheme` and `AppType` build, read
/// from the live theme into `OutsideStyle.swift` (generated). A role names
/// every axis its face has, because a variable font registered once draws its
/// default instance (for Bricolage Grotesque, 96pt ExtraBold at full width)
/// whatever weight a plain font asks for.
struct OutsideRole {
  let family: String
  let size: CGFloat
  /// The line's height as a multiple of [size], as Flutter's `height`.
  let lineHeight: CGFloat
  /// In points at [size].
  let tracking: CGFloat
  let axes: [OutsideAxis]
  let tabular: Bool
}

extension OutsideRole {
  /// The PostScript name of each face's default instance, read from the
  /// bundled files (not guessed): the name a descriptor starts from before
  /// the axes move it. Bricolage's default is its 96pt ExtraBold drawing,
  /// which is why its name is not `-Regular`.
  private static let faces = [
    "Bricolage Grotesque": "BricolageGrotesque-96ptExtraBold",
    "Onest": "Onest-Regular",
    "Geist Mono": "GeistMono-Regular",
  ]

  /// The scale a role follows with Dynamic Type: its nearest system style, so
  /// a figure grows as a title does and a caption as a caption.
  private var textStyle: UIFont.TextStyle {
    switch size {
    case 34...: return .largeTitle
    case 19...: return .title3
    case 14...: return .subheadline
    case 13...: return .footnote
    default: return .caption1
    }
  }

  /// [size] at the Dynamic Type size the view is in. It is read from the
  /// environment, where `.dynamicTypeSize(...)` caps it, rather than from the
  /// system: `UIFontMetrics` alone would ignore the cap every widget root sets.
  func scaledSize(for dynamicType: DynamicTypeSize) -> CGFloat {
    let category = UIContentSizeCategory(dynamicType)
    return UIFontMetrics(forTextStyle: textStyle).scaledValue(
      for: size, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
  }

  func uiFont(for dynamicType: DynamicTypeSize) -> UIFont {
    let size = scaledSize(for: dynamicType)
    guard let name = Self.faces[family], UIFont(name: name, size: size) != nil else {
      // The face did not register: the system's, at the role's weight, still
      // legible and never a missing glyph.
      let wght = axes.first { $0.tag == "wght" }?.value ?? 400
      let weight: UIFont.Weight =
        wght >= 700 ? .bold : wght >= 600 ? .semibold : wght >= 500 ? .medium : .regular
      return .systemFont(ofSize: size, weight: weight)
    }
    var variations: [NSNumber: NSNumber] = [:]
    for axis in axes {
      variations[NSNumber(value: axis.identifier)] = NSNumber(value: Double(axis.value))
    }
    var attributes: [UIFontDescriptor.AttributeName: Any] = [
      .name: name,
      UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
    ]
    if tabular {
      // `tnum`: a figure that updates in place must not jitter.
      attributes[.featureSettings] = [
        [
          UIFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): "tnum",
          UIFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): 1,
        ]
      ]
    }
    return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
  }
}

private struct OutsideTypeStyle: ViewModifier {
  let role: OutsideRole
  let lines: Int
  @Environment(\.dynamicTypeSize) private var dynamicType

  func body(content: Content) -> some View {
    let font = role.uiFont(for: dynamicType)
    // The line box the app draws, not the face's own: Flutter spreads the
    // leading evenly above and below, which is what a frame of that height
    // does to a single line. Lines that wrap take the difference as spacing.
    let box = role.lineHeight * font.pointSize
    let styled = content
      .font(Font(font as CTFont))
      .tracking(role.tracking * font.pointSize / role.size)
    if lines == 1 {
      styled.lineLimit(1).frame(height: box)
    } else {
      styled.lineLimit(lines).lineSpacing(box - font.lineHeight)
    }
  }
}

extension View {
  /// Draws text in [role]: its face, axes, tracking and line height, scaled
  /// with Dynamic Type. More than one line only where a thing is worth it
  /// (a title); everything else truncates rather than push its neighbours.
  func outsideType(_ role: OutsideRole, lines: Int = 1) -> some View {
    modifier(OutsideTypeStyle(role: role, lines: lines))
  }
}
