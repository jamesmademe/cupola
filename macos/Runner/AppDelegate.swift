import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A `cupola://` link clicked on the Mac (an invite, a page of the app).
  ///
  /// Handed to `LinkHandoffChannel`, which pushes it to the router as soon as
  /// the router is listening: at once with Cupola open, after the start when the
  /// link is what opened it.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme == "cupola" {
      LinkHandoffChannel.open(url)
    }
  }
}
