import CoreGraphics
import Foundation
import ImageIO

/// The App Group the app and the extension both carry in their entitlements:
/// the one folder they share. Kept in step with `OutsideChannel.group` in
/// `Runner/AppDelegate.swift`, which names the same group for the app's side.
let outsideGroup = "group.com.matthwlabs.cupola"

/// Where the app writes what the widgets draw (`outside_shelf.dart`): the
/// snapshot, and the pictures it names beside it.
enum OutsideShelf {
  /// The most pixels a point is ever drawn with on a phone: a picture is
  /// never kept sharper than the screen can show it.
  private static let pixelsPerPoint: CGFloat = 3

  private static var folder: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: outsideGroup)?
      .appendingPathComponent("outside", isDirectory: true)
  }

  /// The snapshot on disk, or nil when there is none or it is not one this
  /// code reads (another version, a file half written, nothing at all).
  static func read() -> OutsideSnapshot? {
    guard let folder,
      let data = try? Data(contentsOf: folder.appendingPathComponent("outside.json"))
    else { return nil }
    return try? JSONDecoder().decode(OutsideSnapshot.self, from: data)
  }

  /// The picture [name] in `outside_pictures/`, decoded no larger than
  /// [size] points needs to cover (the way `scaledToFill` draws it). A widget
  /// lives in about 30 MB: a poster decoded whole is most of it, and
  /// ImageIO's thumbnail path decodes straight to the smaller size without
  /// ever holding the large one.
  static func picture(named name: String, covering size: CGSize) -> CGImage? {
    guard let folder, !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
    let url = folder.appendingPathComponent("outside_pictures").appendingPathComponent(name)
    guard
      let source = CGImageSourceCreateWithURL(
        url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { return nil }

    // The thumbnail's longest side such that the picture still covers
    // [size] in pixels, and never above the picture's own.
    let fill = max(
      size.width * pixelsPerPoint / width, size.height * pixelsPerPoint / height)
    let longest = max(width, height) * min(1, fill)
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      // Decoded now, in the provider, and not on the render path.
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(longest.rounded(.up)),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }
}
