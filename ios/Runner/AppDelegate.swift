import Flutter
import Network
import UIKit
import UserNotifications
import WidgetKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets a notification tapped while the app is running reach Dart.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    // The widgets' and notifications' read with the app off the screen
    // (`outside_background.dart`): a BGAppRefreshTask, which iOS runs when it
    // decides to, no sooner than fifteen minutes after the last. Registered
    // here because iOS takes a task's handler only before launch finishes; the
    // engine it runs in gets the app's plugins, so the read reaches the
    // servers, the keychain and the disk the way the app does.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      // The run writes where the widgets read, in this engine as in the app's.
      if let registrar = registry.registrar(forPlugin: "OutsideChannel") {
        OutsideChannel.register(with: registrar.messenger())
      }
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.matthwlabs.cupola.outside",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    SecureClipboardChannel.register(with: messenger)
    LocalNetworkAccessChannel.register(with: messenger)
    OutsideChannel.register(with: messenger)
    TestlabIdentityChannel.register(with: messenger)
  }
}

/// The identity a seeded build can prove from inside its own process.
///
/// `Platform.environment` carries no `HOME` on iOS, and the data container's
/// path is a UUID rather than the bundle id, so neither can prove which app is
/// running. `Bundle.main` and `NSHomeDirectory()` are the process's actual
/// identity and destination, not a guess from an environment variable. The
/// lab's seed refuses to write unless they name the testlab build and its own
/// App Group.
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

/// What Cupola shows outside itself (`outside_native.dart`): the folder the
/// widgets read, which only the App Group can name, and the widgets. Android
/// answers the same three methods in `packages/outside_channel`, a plugin
/// because the background read runs in an engine of WorkManager's own.
enum OutsideChannel {
  /// The group the extension reads (`outsideGroup` in
  /// `CupolaWidgets/OutsideShelf.swift`) and both entitlements carry: change
  /// one and the others with it, or the widgets read a folder the app never
  /// writes. The build setting lets an isolated build (testlab, dev) carry an
  /// App Group of its own, so it never reads or writes the house's widgets.
  static let group =
    (Bundle.main.object(forInfoDictionaryKey: "CupolaAppGroup") as? String)
    ?? "group.com.matthwlabs.cupola"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "cupola/outside", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "sharedFolder":
        // Nil when the build carries no App Group: Dart keeps the file in
        // the app's own folder, and no widget reads it.
        let folder = FileManager.default
          .containerURL(forSecurityApplicationGroupIdentifier: group)?
          .appendingPathComponent("outside", isDirectory: true)
        result(folder?.path)
      case "reload":
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      case "installed":
        WidgetCenter.shared.getCurrentConfigurations { answer in
          let any = (try? answer.get())?.isEmpty == false
          DispatchQueue.main.async { result(any) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Copies a credential without letting it reach the user's other devices.
///
/// The general pasteboard syncs through Universal Clipboard, so a plain copy of
/// an API key hands it to every other device signed into the same account.
/// `localOnly` is what keeps it on this one and `expirationDate` is what stops
/// it lingering there; neither is reachable from Flutter's clipboard plumbing:
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

      let seconds = arguments?["expiresInSeconds"] as? Int ?? 0
      result(copySecret(secret, expiresIn: seconds))
    }
  }

  private static func copySecret(_ secret: String, expiresIn seconds: Int) -> Bool {
    // Spelled out rather than taken from UniformTypeIdentifiers: the string is
    // the pasteboard's own identifier and importing a framework for it would be
    // the only new dependency in this file.
    let plainText = "public.utf8-plain-text"
    var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
    if seconds > 0 {
      // UIKit expires the item itself, so the key is gone even if the app never
      // gets to run its own timed clear. That clear stays as well: it is the
      // only half of this that works on every OS.
      options[.expirationDate] = Date().addingTimeInterval(TimeInterval(seconds))
    }

    UIPasteboard.general.setItems([[plainText: secret]], options: options)
    return true
  }
}

/// Answers whether iOS is letting Cupola onto the local network, and takes the
/// user to the toggle when it is not.
///
/// Every service Cupola exists to manage lives on the user's own network, and
/// since iOS 14 the first connection to one raises a permission alert. The
/// connection that raised it fails, silently, as "no route to host", so
/// without this channel a first-run test reports an unreachable server while the
/// alert asking to make it reachable is still on screen. Dart calls `resolve`
/// only *after* such a failure, which is what makes it safe: the alert is
/// already up, and this waits for the answer rather than adding a second prompt.
///
/// There is no API that reads this permission. Apple's own answer, and the one
/// implemented here, is to advertise a throwaway Bonjour service, browse for it,
/// and watch what the browser says: finding it proves access, and
/// `kDNSServiceErr_PolicyDenied` proves refusal.
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
        // Lands on Cupola's own page, which is where the Local Network toggle
        // is: deep-linking any further into Settings is not something iOS
        // offers, and the sentence beside the button names the rest of the path.
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// The probe in flight, and everyone waiting on it.
  ///
  /// One probe answers every waiter, which is what keeps the ten services
  /// onboarding tests in parallel from each standing up their own Bonjour
  /// listener to learn the same fact. Coalescing lives here rather than in Dart
  /// because this side can also *cancel*; a shared future on the Dart side is a
  /// promise nothing completes once the caller that owned it is gone. A waiter
  /// that arrives late inherits the running probe's deadline rather than
  /// extending it; the verdict is the same either way.
  ///
  /// `AnyObject` so this property does not inherit the probe's own availability.
  private static var live: AnyObject?
  private static var waiting: [FlutterResult] = []

  private static func resolve(timeout: TimeInterval, result: @escaping FlutterResult) {
    // Before iOS 14 there is no permission to be blocked by, so there is
    // nothing here that could explain a failure.
    guard #available(iOS 14.0, *) else {
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
}

/// One local-network verdict, from a Bonjour service that exists for no other
/// purpose.
@available(iOS 14.0, *)
private final class LocalNetworkProbe {
  /// Matches `NSBonjourServices` in Info.plist. Bonjour caps the name at 15
  /// characters, which is why it is not spelled `_cupola-lan-check`.
  private static let serviceType = "_cupola-check._tcp"

  /// `kDNSServiceErr_PolicyDenied`, spelled out rather than imported: the
  /// constant lives in `dnssd`, and Network only guarantees the error *case*.
  private static let policyDenied: Int32 = -65570

  /// A grant that lands later than this was answered by a person, so the
  /// connection that failed a moment ago was dialled through a gate that has
  /// since opened and deserves a retry.
  ///
  /// Measured rather than guessed: a cold Bonjour registration and discovery on an
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

    // The listener is what gives the browser something to find, and finding it
    // is the only positive proof of access. A listener that cannot start is
    // deliberately *not* fatal to the probe: the browser alone still reports a
    // refusal, and reporting "unknown" early would throw that away.
    do {
      let listener = try NWListener(using: .tcp)
      listener.service = NWListener.Service(name: name, type: Self.serviceType)
      // Required: a listener with no handler for incoming connections fails
      // instead of starting. Nothing ever connects to this one.
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

    // The alert can sit unanswered forever; the user may have put the phone
    // down. `unknown` claims nothing, so Dart reports the connection failure it
    // already had.
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

  /// Only the mDNS refusal counts, and deliberately not a POSIX `EACCES`/`EPERM`
  /// alongside it: a sandbox that may browse but not advertise fails the same way,
  /// and reading that as a refusal would tell a user whose permission is switched
  /// on to go and switch it on. Missing a refusal costs the old behaviour; the
  /// plain connection failure, while inventing one sends the user somewhere there
  /// is nothing to fix.
  private static func isPolicyDenied(_ error: NWError) -> Bool {
    if case .dns(let code) = error { return code == policyDenied }
    return false
  }
}
