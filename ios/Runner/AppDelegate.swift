import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var powerChannel: FlutterMethodChannel?
  private var originalScreenBrightness: CGFloat?
  private var originalIdleTimerDisabled = false
  private var requestedScreenBrightness: CGFloat?
  private var requestedKeepScreenOn = false
  private var originalBatteryMonitoring = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "smart_keys/power",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    powerChannel = channel
    originalBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
    originalIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    UIDevice.current.isBatteryMonitoringEnabled = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(batteryStateChanged),
      name: UIDevice.batteryStateDidChangeNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sceneWillResignActive),
      name: UIScene.willDeactivateNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(sceneDidBecomeActive),
      name: UIScene.didActivateNotification,
      object: nil
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "UNAVAILABLE", message: "App delegate released", details: nil)); return }
      switch call.method {
      case "isPluggedIn":
        result(self.isPluggedIn)
      case "setAppBrightness":
        if let arguments = call.arguments as? [String: Any], let value = arguments["brightness"] as? NSNumber {
          if self.originalScreenBrightness == nil { self.originalScreenBrightness = UIScreen.main.brightness }
          self.requestedScreenBrightness = CGFloat(value.doubleValue.clamped(to: 0...1))
          UIScreen.main.brightness = self.requestedScreenBrightness!
        } else {
          self.requestedScreenBrightness = nil
          if let previous = self.originalScreenBrightness { UIScreen.main.brightness = previous }
        }
        result(nil)
      case "setKeepScreenOn":
        let arguments = call.arguments as? [String: Any]
        self.requestedKeepScreenOn = arguments?["enabled"] as? Bool ?? false
        UIApplication.shared.isIdleTimerDisabled = self.requestedKeepScreenOn || self.originalIdleTimerDisabled
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var isPluggedIn: Bool? {
    switch UIDevice.current.batteryState {
    case .charging, .full: return true
    case .unplugged: return false
    case .unknown: return nil
    @unknown default: return nil
    }
  }

  @objc private func batteryStateChanged() {
    powerChannel?.invokeMethod("powerStateChanged", arguments: isPluggedIn)
  }

  @objc private func sceneWillResignActive() {
    restoreScreenAndIdleState()
  }

  @objc private func sceneDidBecomeActive() {
    if let brightness = requestedScreenBrightness { UIScreen.main.brightness = brightness }
    UIApplication.shared.isIdleTimerDisabled = requestedKeepScreenOn || originalIdleTimerDisabled
  }

  private func restoreScreenAndIdleState() {
    if let previous = originalScreenBrightness { UIScreen.main.brightness = previous }
    UIApplication.shared.isIdleTimerDisabled = originalIdleTimerDisabled
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    restoreScreenAndIdleState()
    UIDevice.current.isBatteryMonitoringEnabled = originalBatteryMonitoring
    NotificationCenter.default.removeObserver(self)
    super.applicationWillTerminate(application)
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
