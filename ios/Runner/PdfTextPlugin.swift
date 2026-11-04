import Flutter
import PDFKit

/// Lee el texto de un PDF con PDFKit, dentro del iPhone (ni el archivo ni la
/// contraseña salen de él, y la contraseña no se registra).
/// Canal `outflow/pdf`, método `readText({path, password})` → texto.
final class PdfTextPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "outflow/pdf", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PdfTextPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "readText" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String else {
      result(FlutterError(code: "pdf", message: "No se pudo abrir el PDF.", details: nil))
      return
    }
    let password = args["password"] as? String

    DispatchQueue.global(qos: .userInitiated).async {
      guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "pdf", message: "No se pudo abrir el PDF.", details: nil))
        }
        return
      }
      if document.isLocked {
        guard let password = password else {
          DispatchQueue.main.async {
            result(FlutterError(code: "password_required", message: nil, details: nil))
          }
          return
        }
        if !document.unlock(withPassword: password) {
          DispatchQueue.main.async {
            result(FlutterError(code: "wrong_password", message: nil, details: nil))
          }
          return
        }
      }
      var pages: [String] = []
      for index in 0..<document.pageCount {
        if let text = document.page(at: index)?.string {
          pages.append(text)
        }
      }
      let text = pages.joined(separator: "\n")
      DispatchQueue.main.async { result(text) }
    }
  }
}
