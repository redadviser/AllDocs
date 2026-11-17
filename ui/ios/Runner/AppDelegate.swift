import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AllDocsICloud") {
      ICloudChannel.register(with: registrar.messenger())
    }
  }
}

/// The iCloud container for backups (ICloudProvider on the Dart side).
/// File reads and writes happen in Dart; this only finds the container and
/// brings back files iOS evicted to save space.
enum ICloudChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "alldocs/icloud", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      // Both can block for a while: never on the main thread.
      DispatchQueue.global(qos: .userInitiated).async {
        let reply: Any?
        switch call.method {
        case "documentsPath":
          reply = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .path
        case "download":
          let path = (call.arguments as? [String: Any])?["path"] as? String
          reply = path.map { download(URL(fileURLWithPath: $0)) } ?? false
        default:
          reply = FlutterMethodNotImplemented
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  private static func download(_ url: URL, timeout: TimeInterval = 120) -> Bool {
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: url)
    } catch {
      return false
    }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      var fresh = url
      fresh.removeAllCachedResourceValues()
      let status = try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        .ubiquitousItemDownloadingStatus
      if status == .current { return true }
      Thread.sleep(forTimeInterval: 0.3)
    }
    return false
  }
}
