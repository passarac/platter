import Flutter

/// Lets Dart run and watch the food scan: "start", "stop" and "meals" on
/// `platter/food_scan`, and progress on `platter/food_scan/progress`.
final class FoodScanPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let service = FoodScanService.shared
  private var observer: UUID?

  static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = FoodScanPlugin()
    registrar.addMethodCallDelegate(
      plugin,
      channel: FlutterMethodChannel(
        name: "platter/food_scan", binaryMessenger: registrar.messenger()))
    FlutterEventChannel(
      name: "platter/food_scan/progress",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(plugin)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "start":
        try service.start()
        result(nil)
      case "stop":
        service.stop()
        result(nil)
      case "meals":
        try service.meals { meals in result(meals.map(Self.encode)) }
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(
        FlutterError(
          code: "scan_failed", message: String(describing: error),
          details: nil))
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    observer.map(service.removeObserver)
    observer = service.observe { events(Self.encode($0)) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observer.map(service.removeObserver)
    observer = nil
    return nil
  }

  private static func encode(_ progress: ScanProgress) -> [String: Any] {
    [
      "total": progress.total,
      "checked": progress.checked,
      "meals": progress.meals,
      "maybes": progress.maybes,
      "waitingForWiFi": progress.waitingForWiFi,
      "unavailable": progress.unavailable,
      "running": progress.running,
      "preview": progress.preview,
    ]
  }

  private static func encode(_ meal: ScanResult) -> [String: Any] {
    [
      "id": meal.id,
      "taken": meal.taken.map { Int($0.timeIntervalSince1970 * 1000) as Any }
        ?? NSNull(),
      "verdict": meal.verdict.rawValue,
      "score": Double(meal.score),
    ]
  }
}
