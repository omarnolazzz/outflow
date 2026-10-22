import Flutter
import UIKit
import Vision

/// Lee el texto de una foto con Vision, dentro del iPhone (la foto no sale de él).
/// Canal `outflow/ocr`, método `recognizeText({path})` → texto por líneas.
final class TextRecognitionPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "outflow/ocr", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TextRecognitionPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognizeText" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let image = UIImage(contentsOfFile: path),
          let cgImage = image.cgImage else {
      result(FlutterError(code: "image", message: "No se pudo abrir la foto.", details: nil))
      return
    }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)

    DispatchQueue.global(qos: .userInitiated).async {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["es-ES", "en-US"]
      let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
      do {
        try handler.perform([request])
        let text = TextRecognitionPlugin.lines(from: request.results ?? []).joined(separator: "\n")
        DispatchQueue.main.async { result(text) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "vision", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// Agrupa los fragmentos en renglones (de arriba abajo, de izquierda a
  /// derecha), para que "PATATAS BRAVAS" y "13,50" queden en la misma línea.
  static func lines(from observations: [VNRecognizedTextObservation]) -> [String] {
    let items = observations
      .compactMap { obs -> (CGRect, String)? in
        guard let text = obs.topCandidates(1).first?.string else { return nil }
        return (obs.boundingBox, text)
      }
      .sorted { $0.0.midY > $1.0.midY }

    var rows: [[(CGRect, String)]] = []
    for item in items {
      if let reference = rows.last?.first, abs(reference.0.midY - item.0.midY) < reference.0.height * 0.5 {
        rows[rows.count - 1].append(item)
      } else {
        rows.append([item])
      }
    }
    return rows.map { row in row.sorted { $0.0.minX < $1.0.minX }.map { $0.1 }.joined(separator: " ") }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .down: self = .down
    case .left: self = .left
    case .right: self = .right
    case .upMirrored: self = .upMirrored
    case .downMirrored: self = .downMirrored
    case .leftMirrored: self = .leftMirrored
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
