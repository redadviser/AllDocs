import Flutter
import UIKit
import Vision

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AllDocsOCR") {
      OCRChannel.register(with: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AllDocsStorage") {
      StorageChannel.register(with: registrar.messenger())
    }
  }
}

/// Free space on the volume holding a path (FreeSpace on the Dart side),
/// checked before encrypting the library, which needs room for a copy.
/// "Important usage" counts space iOS would free by purging caches.
enum StorageChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "alldocs/storage", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "freeBytes",
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [
          .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        if let important = values.volumeAvailableCapacityForImportantUsage {
          result(NSNumber(value: important))
        } else if let available = values.volumeAvailableCapacity {
          result(NSNumber(value: available))
        } else {
          result(FlutterError(code: "stat_failed", message: "no capacity", details: nil))
        }
      } catch {
        result(FlutterError(code: "stat_failed", message: error.localizedDescription, details: nil))
      }
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

/// On-device OCR with Apple Vision (TextRecognition on the Dart side).
/// Boxes go back in image pixels with a top-left origin, like ML Kit's.
enum OCRChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "alldocs/ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let path = (call.arguments as? [String: Any])?["path"] as? String,
        let image = UIImage(contentsOfFile: path)?.cgImage
      else {
        result(FlutterError(code: "bad_args", message: "Unreadable image", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let reply: Any
        do {
          reply = try recognize(image, orientation: orientation(of: path))
        } catch {
          reply = FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil)
        }
        DispatchQueue.main.async { result(reply) }
      }
    }
  }

  private static func orientation(of path: String) -> CGImagePropertyOrientation {
    let raw = UIImage(contentsOfFile: path)?.imageOrientation ?? .up
    switch raw {
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    default: return .up
    }
  }

  private static func recognize(
    _ image: CGImage, orientation: CGImagePropertyOrientation
  ) throws -> [String: Any] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["pt-BR", "en-US", "es-ES", "fr-FR"]  // Vision has no pt-PT; pt-BR reads it fine
    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])

    // Vision's boxes are normalized to the upright image.
    let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
    let width = Double(rotated ? image.height : image.width)
    let height = Double(rotated ? image.width : image.height)
    var lines: [[String: Any]] = []
    var text: [String] = []
    for observation in request.results ?? [] {
      guard let candidate = observation.topCandidates(1).first else { continue }
      let box = observation.boundingBox
      text.append(candidate.string)
      lines.append([
        "text": candidate.string,
        "left": box.minX * width,
        "top": (1 - box.maxY) * height,
        "width": box.width * width,
        "height": box.height * height,
      ])
    }
    return ["text": text.joined(separator: "\n"), "lines": lines]
  }
}
