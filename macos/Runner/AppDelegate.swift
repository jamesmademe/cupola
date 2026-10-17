import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// When the app finished launching: a link that opens a closed Cupola
  /// arrives a moment after that, before the router is listening.
  private var launchedAt = Date()

  /// How long after launch a link waits before it is handed over, so the
  /// router that reads it has been built.
  private static let routerReadyAfter: TimeInterval = 3

  override func applicationDidFinishLaunching(_ notification: Notification) {
    launchedAt = Date()
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A `cupola://` link clicked on the Mac (an invite, a page of the app).
  ///
  /// iOS hands such a link to the router by itself (`FlutterDeepLinkingEnabled`);
  /// the macOS embedder does not, so it is pushed here on the channel the
  /// framework's router listens to, exactly as iOS pushes it.
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme == "cupola" {
      let wait = max(0, AppDelegate.routerReadyAfter - Date().timeIntervalSince(launchedAt))
      DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
        self?.pushRoute(url.absoluteString)
      }
    }
  }

  private func pushRoute(_ location: String) {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else { return }
    let channel = FlutterMethodChannel(
      name: "flutter/navigation",
      binaryMessenger: controller.engine.binaryMessenger,
      codec: FlutterJSONMethodCodec.sharedInstance()
    )
    channel.invokeMethod("pushRouteInformation", arguments: ["location": location])
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
  }
}
