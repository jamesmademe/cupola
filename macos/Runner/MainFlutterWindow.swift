import Cocoa
import FlutterMacOS
import Network
import window_manager

class MainFlutterWindow: NSWindow {
  // Hidden until Flutter has drawn into it: `DesktopWindow.showWhenDrawn`
  // shows it. Shown at launch, it was black for as long as the start took.
  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // A small phone's width: below the 720pt compact artboard the window paints
    // the phone layout rather than stopping. Mirrors
    // `AppBreakpoints.desktopMinimumWindow`, which window_manager applies too.
    self.minSize = NSSize(width: 360, height: 450)

    // The strip Flutter draws under the traffic lights, set before the saved
    // frame is restored. `DesktopWindow.ensureReady` asks window_manager for the
    // same style once Dart runs; applied only then, the frame restored for a
    // titled window lost the title bar's height on every launch.
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)

    // An empty unified toolbar: it makes the title bar the 52pt band Flutter
    // draws its toolbar in (`WindowChrome.macosHeight`), and centres the
    // traffic lights in it, as a Mac's own windows with a sidebar have them.
    // It holds no item: every control in the band is Flutter's.
    let toolbar = NSToolbar(identifier: "CupolaWindowToolbar")
    toolbar.showsBaselineSeparator = false
    self.toolbar = toolbar
    self.toolbarStyle = .unified

    let autosaveName = "CupolaMainWindow"
    let isFirstLaunch =
      UserDefaults.standard.object(forKey: "NSWindow Frame \(autosaveName)") == nil

    if isFirstLaunch {
      // First launch: the size the desktop UI is drawn at, centred.
      self.setContentSize(NSSize(width: 1440, height: 900))
      if let screen = NSScreen.main {
        let visible = screen.visibleFrame
        let frame = self.frame
        self.setFrameOrigin(NSPoint(
          x: visible.midX - frame.width / 2,
          y: visible.midY - frame.height / 2,
        ))
      }
    }
    // Register autosave on every launch: first launch saves the new default,
    // subsequent launches restore the user's last frame (size + position).
    _ = self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    SecureClipboardChannel.register(with: flutterViewController.engine.binaryMessenger)

    LocalNetworkAccessChannel.register(
      with: flutterViewController.engine.binaryMessenger
    )

    LinkHandoffChannel.register(
      with: flutterViewController.engine.binaryMessenger,
      window: self
    )

    TestlabIdentityChannel.register(
      with: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}

/// The identity a seeded build can prove from inside its own process.
///
/// `Platform.environment` carries no `HOME` on iOS, and the data container's
/// path is a UUID rather than the bundle id, so neither can prove which app is
/// running. `Bundle.main` and `NSHomeDirectory()` are the process's actual
/// identity and destination, not a guess from an environment variable. The
/// lab's seed refuses to write unless they name the testlab build.
enum TestlabIdentityChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "cupola/testlab",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "identity" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let group =
        (Bundle.main.object(forInfoDictionaryKey: "CupolaAppGroup") as? String)
        ?? ""
      let folder = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: group)?
        .path
      result([
        "bundle": Bundle.main.bundleIdentifier ?? "",
        "home": NSHomeDirectory(),
        "group": group,
        "groupFolder": folder ?? "",
        "preferences":
          NSHomeDirectory() + "/Library/Preferences/"
          + (Bundle.main.bundleIdentifier ?? "") + ".plist",
      ])
    }
  }
}

/// Holds a `cupola://` link until the router is listening, then hands it over.
///
/// iOS routes a link by itself (`FlutterDeepLinkingEnabled`); the macOS embedder
/// does not, so the runner pushes it on `flutter/navigation`, the channel the
/// framework's router listens to. A push sent before the router has subscribed
/// is dropped without a word, and a closed Cupola opened by a link receives it
/// while Dart is still starting, which can mean waiting on a Keychain prompt.
/// So every link waits here until Dart says `routerReady` after its first
/// frame: `LinkHandoff` in `lib/core/platform/link_handoff.dart`. A fixed delay
/// used to stand in for that signal, and lost the link on any slower start.
enum LinkHandoffChannel {
  private static var navigation: FlutterMethodChannel?
  private static weak var window: NSWindow?
  private static var routerReady = false
  private static var pending: [String] = []

  static func register(with messenger: FlutterBinaryMessenger, window: NSWindow) {
    navigation = FlutterMethodChannel(
      name: "flutter/navigation",
      binaryMessenger: messenger,
      codec: FlutterJSONMethodCodec.sharedInstance()
    )
    self.window = window

    let channel = FlutterMethodChannel(
      name: "com.matthwlabs.cupola/links",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "routerReady" else {
        result(FlutterMethodNotImplemented)
        return
      }
      routerReady = true
      let held = pending
      pending = []
      for location in held { push(location) }
      result(nil)
    }
  }

  /// A link clicked on the Mac: handed over now, or held until Dart is ready.
  /// Only ever called on the main thread, like the channel's handler, which is
  /// what lets `routerReady` and `pending` go unguarded.
  static func open(_ url: URL) {
    let location = url.absoluteString
    if routerReady {
      push(location)
    } else {
      pending.append(location)
    }
  }

  private static func push(_ location: String) {
    navigation?.invokeMethod("pushRouteInformation", arguments: ["location": location])
    window?.makeKeyAndOrderFront(nil)
  }
}

/// Copies a credential without letting it reach the user's other devices.
///
/// The general pasteboard syncs through Universal Clipboard, so a plain copy of
/// an API key hands it to every Mac, iPhone and iPad signed into the same
/// account. `NSPasteboard.ContentsOptions.currentHostOnly` is what keeps a clip
/// on this machine, and it is not reachable from Flutter's clipboard plumbing;
/// hence this channel. Dart falls back to a plain copy whenever `copySecret`
/// answers false, so nothing here can break the copy button.
enum SecureClipboardChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.matthwlabs.cupola/secure_clipboard",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "copySecret" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let arguments = call.arguments as? [String: Any]
      guard let secret = arguments?["secret"] as? String, !secret.isEmpty else {
        result(false)
        return
      }

      result(copySecret(secret))
    }
  }

  private static func copySecret(_ secret: String) -> Bool {
    // No availability guard: `prepareForNewContents(with:)` and
    // `.currentHostOnly` are both macOS 10.12 API and this app deploys to
    // 12.0, so every version that can run it can harden the clip. The old
    // `#available(macOS 11.0, *)` guard returned false on pre-11 systems,
    // which sent `_copyApiKey` down its plain-copy fallback and
    // put the API key on the syncing general pasteboard: the exact leak this
    // channel exists to close, disabled on the oldest OS it supports.
    let pasteboard = NSPasteboard.general
    // Replaces clearContents(): it clears and applies the options to whatever is
    // written next. AppKit has no pasteboard expiry, so the Dart-side timed
    // clear stays the mitigation for how long the key lingers.
    pasteboard.prepareForNewContents(with: .currentHostOnly)
    return pasteboard.setString(secret, forType: .string)
  }
}

/// Answers whether macOS is letting Cupola onto the local network.
///
/// The same permission iOS 14 introduced arrived on the Mac with macOS 15, and it
/// fails the same silent way: a service on the LAN simply stops answering, so a
/// connection test blames the address. Dart calls `resolve` only after such a
/// failure; see the iOS twin of this channel in `ios/Runner/AppDelegate.swift`,
/// which carries the full reasoning.
///
/// One deliberate difference from iOS: the sandbox lets a release build browse
/// for Bonjour services (`network.client`) but not advertise one
/// (`network.server`, which only the debug profile grants). So the listener half
/// of the probe is expected to fail in a release build, and the probe is built to
/// survive that: a refusal is still detected (the *browser* is what reports it),
/// while a grant comes back as `unknown`, which claims nothing and leaves the
/// original connection failure exactly as it was. Granting the entitlement in
/// `Release.entitlements` would buy the positive answer, at the cost of shipping
/// a listening socket in a client app.
enum LocalNetworkAccessChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.matthwlabs.cupola/local_network",
      binaryMessenger: messenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "resolve":
        let arguments = call.arguments as? [String: Any]
        let milliseconds = arguments?["timeoutMs"] as? Int ?? 20000
        resolve(timeout: TimeInterval(milliseconds) / 1000, result: result)
      case "openSettings":
        result(openPrivacySettings())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The probe in flight, and everyone waiting on it.
  ///
  /// One probe answers every waiter; see the iOS twin for why this lives here
  /// rather than in Dart.
  ///
  /// `AnyObject` so this property does not inherit the probe's own availability.
  private static var live: AnyObject?
  private static var waiting: [FlutterResult] = []

  private static func resolve(timeout: TimeInterval, result: @escaping FlutterResult) {
    // Before Sequoia the Mac never gated the local network.
    guard #available(macOS 15.0, *) else {
      result("unrestricted")
      return
    }

    waiting.append(result)
    // Already asking. The running probe answers this caller too.
    if live != nil { return }

    let probe = LocalNetworkProbe()
    live = probe
    probe.run(timeout: timeout) { verdict in
      // Back on the platform thread, both because `FlutterResult` expects it and
      // because `live` and `waiting` are only ever touched there.
      DispatchQueue.main.async {
        live = nil
        let pending = waiting
        waiting = []
        for answer in pending { answer(verdict) }
      }
    }
  }

  /// Opens the Local Network list in System Settings, falling back to the pane
  /// that contains it when the anchor is not honoured. The anchor names are
  /// Apple's, undocumented, and have been renamed between releases before.
  private static func openPrivacySettings() -> Bool {
    let anchored = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
    )
    if let anchored, NSWorkspace.shared.open(anchored) { return true }
    guard
      let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security")
    else { return false }
    return NSWorkspace.shared.open(pane)
  }
}

/// One local-network verdict, from a Bonjour service that exists for no other
/// purpose. Mirrors `LocalNetworkProbe` in `ios/Runner/AppDelegate.swift`.
@available(macOS 15.0, *)
private final class LocalNetworkProbe {
  /// Matches `NSBonjourServices` in Info.plist; Bonjour caps the name at 15
  /// characters.
  private static let serviceType = "_cupola-check._tcp"

  /// `kDNSServiceErr_PolicyDenied`, spelled out rather than imported from
  /// `dnssd`.
  private static let policyDenied: Int32 = -65570

  /// A grant that lands later than this was answered by a person, so the
  /// connection that failed a moment ago was dialled through a gate that has
  /// since opened and deserves a retry.
  ///
  /// See the iOS twin: measured rather than guessed: a cold Bonjour registration and discovery on an
  /// already-granted machine took 0.97s, so the obvious ~1s threshold sits right
  /// on top of it. The asymmetry decides the rest: reading a fast human as
  /// `granted` costs them one tap on Test, while reading a slow round trip as
  /// `just_granted` re-runs a doomed connection in full.
  private static let humanDelay: TimeInterval = 2.5

  private let queue = DispatchQueue(label: "com.matthwlabs.cupola.local-network")
  private let name = UUID().uuidString
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var settled = false
  private var startedAt = Date()
  private var completion: ((String) -> Void)?

  func run(timeout: TimeInterval, completion: @escaping (String) -> Void) {
    queue.async { self.start(timeout: timeout, completion: completion) }
  }

  private func start(timeout: TimeInterval, completion: @escaping (String) -> Void) {
    self.completion = completion
    startedAt = Date()

    // Expected to fail in a sandboxed release build, and deliberately not fatal:
    // the browser alone still reports a refusal.
    do {
      let listener = try NWListener(using: .tcp)
      listener.service = NWListener.Service(name: name, type: Self.serviceType)
      listener.newConnectionHandler = { $0.cancel() }
      listener.start(queue: queue)
      self.listener = listener
    } catch {
      self.listener = nil
    }

    let parameters = NWParameters()
    parameters.includePeerToPeer = true
    let browser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil),
      using: parameters
    )
    browser.stateUpdateHandler = { [weak self] state in
      switch state {
      case .waiting(let error), .failed(let error):
        if Self.isPolicyDenied(error) { self?.settle("denied") }
      default:
        break
      }
    }
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      guard let self else { return }
      let found = results.contains { candidate in
        if case let .service(name, _, _, _) = candidate.endpoint {
          return name == self.name
        }
        return false
      }
      guard found else { return }
      let waited = Date().timeIntervalSince(self.startedAt)
      self.settle(waited > Self.humanDelay ? "just_granted" : "granted")
    }
    browser.start(queue: queue)
    self.browser = browser

    queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
      self?.settle("unknown")
    }
  }

  /// Always on `queue`, which is what makes the once-only guard sound.
  private func settle(_ verdict: String) {
    guard !settled else { return }
    settled = true
    listener?.cancel()
    listener = nil
    browser?.cancel()
    browser = nil
    let finish = completion
    completion = nil
    finish?(verdict)
  }

  /// Only the mDNS refusal counts; see the iOS twin. It matters more here: this
  /// sandbox may browse but not advertise in a release build, and a POSIX error
  /// read as a refusal would tell a Mac user whose permission is switched on to go
  /// and switch it on.
  private static func isPolicyDenied(_ error: NWError) -> Bool {
    if case .dns(let code) = error { return code == policyDenied }
    return false
  }
}
