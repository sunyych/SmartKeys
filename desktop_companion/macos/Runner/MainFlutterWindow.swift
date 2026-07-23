import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var systemControlChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.isReleasedWhenClosed = false
    self.orderOut(nil)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "lumiakeys/system_control",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setDark",
            let arguments = call.arguments as? [String: Any],
            let enabled = arguments["enabled"] as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.setDark(enabled)
      result(nil)
    }
    systemControlChannel = channel

    super.awakeFromNib()
  }

  private func setDark(_ enabled: Bool) {
    // macOS system-defined auxiliary key types from IOKit hidsystem/ev_keymap.h.
    let displayKey: Int32 = enabled ? 3 : 2
    let keyboardIlluminationKey: Int32 = enabled ? 22 : 21
    for _ in 0..<20 {
      postAuxiliaryKey(displayKey)
    }
    for _ in 0..<16 {
      postAuxiliaryKey(keyboardIlluminationKey)
    }
  }

  private func postAuxiliaryKey(_ keyType: Int32) {
    postAuxiliaryKey(keyType, keyState: 0xA)
    postAuxiliaryKey(keyType, keyState: 0xB)
    Thread.sleep(forTimeInterval: 0.01)
  }

  private func postAuxiliaryKey(_ keyType: Int32, keyState: Int) {
    let event = NSEvent.otherEvent(
      with: .systemDefined,
      location: .zero,
      modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: 0,
      context: nil,
      subtype: 8,
      data1: (Int(keyType) << 16) | (keyState << 8),
      data2: -1
    )
    event?.cgEvent?.post(tap: .cghidEventTap)
  }
}
