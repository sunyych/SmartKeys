import Cocoa
import FlutterMacOS
import ApplicationServices
import Carbon

class MainFlutterWindow: NSWindow {
  private var systemControlChannel: FlutterMethodChannel?
  private var dictationChannel: FlutterMethodChannel?
  private var hotKey: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

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

    let dictation = FlutterMethodChannel(
      name: "lumiakeys/dictation",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    dictation.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "insertText":
        guard let arguments = call.arguments as? [String: Any],
              let text = arguments["text"] as? String else {
          result(["status": "rejected", "reason": "invalid_arguments"])
          return
        }
        result(Self.insertText(text))
      case "validateTarget":
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
          result(["status": "rejected", "reason": "accessibility_permission_missing"])
          return
        }
        guard let target = Self.focusedTarget(), target.pid != ProcessInfo.processInfo.processIdentifier else {
          result(["status": "rejected", "reason": "own_or_invalid_foreground"])
          return
        }
        result(Self.hasHeldModifier() ? ["status": "rejected", "reason": "held_modifier"] : ["status": "ready"])
      case "modifiersHeld":
        result(Self.hasHeldModifier())
      case "accessibilityStatus":
        result(AXIsProcessTrusted() && CGPreflightPostEventAccess())
      case "requestAccessibilityPermission":
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        _ = CGRequestPostEventAccess()
        result(AXIsProcessTrusted() && CGPreflightPostEventAccess())
      case "openAccessibilitySettings":
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
          result(FlutterError(code: "settings_unavailable", message: nil, details: nil))
          return
        }
        NSWorkspace.shared.open(url)
        result(nil)
      case "registerToggleHotkey":
        let args = call.arguments as? [String: Any]
        let shortcut = args?["shortcut"] as? String ?? "ctrlShiftSpace"
        do { try self?.registerToggleHotkey(shortcut); result(true) }
        catch { result(FlutterError(code: "hotkey_registration_failed", message: error.localizedDescription, details: nil)) }
      case "unregisterToggleHotkey":
        self?.unregisterToggleHotkey()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    dictationChannel = dictation

    super.awakeFromNib()
  }

  deinit { unregisterToggleHotkey() }

  private func registerToggleHotkey(_ shortcut: String) throws {
    unregisterToggleHotkey()
    let spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let window = Unmanaged<MainFlutterWindow>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async { window.dictationChannel?.invokeMethod("toggleHotkeyPressed", arguments: nil) }
        return noErr
      },
      1, [spec], Unmanaged.passUnretained(self).toOpaque(), &eventHandler
    )
    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    let identifier = EventHotKeyID(signature: OSType(0x4C4B), id: 1)
    let modifiers: UInt32
    switch shortcut {
    case "ctrlAltSpace": modifiers = UInt32(controlKey | optionKey)
    case "altShiftSpace": modifiers = UInt32(optionKey | shiftKey)
    default: modifiers = UInt32(controlKey | shiftKey)
    }
    let registered = RegisterEventHotKey(
      UInt32(kVK_Space), modifiers, identifier,
      GetApplicationEventTarget(), 0, &hotKey
    )
    guard registered == noErr else {
      RemoveEventHandler(eventHandler!)
      eventHandler = nil
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(registered), userInfo: [NSLocalizedDescriptionKey: "Ctrl+Shift+Space is unavailable"])
    }
  }

  private func unregisterToggleHotkey() {
    if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    if let eventHandler { RemoveEventHandler(eventHandler); self.eventHandler = nil }
  }

  private struct FocusedTarget {
    let pid: pid_t
    let window: AXUIElement
    let element: AXUIElement
  }

  private static func insertText(_ text: String) -> [String: String] {
    guard AXIsProcessTrusted() else { return ["status": "rejected", "reason": "accessibility_permission_missing"] }
    guard CGPreflightPostEventAccess() else { return ["status": "rejected", "reason": "event_permission_missing"] }
    guard !text.isEmpty, text.utf16.count <= 8000 else { return ["status": "rejected", "reason": text.isEmpty ? "empty_text" : "text_too_long"] }
    guard text.unicodeScalars.allSatisfy({ !isUnsupportedControl($0) }) else { return ["status": "rejected", "reason": "unsupported_control_character"] }
    guard let target = focusedTarget(), target.pid != ProcessInfo.processInfo.processIdentifier else {
      return ["status": "rejected", "reason": "own_or_invalid_foreground"]
    }
    guard !hasHeldModifier() else { return ["status": "rejected", "reason": "held_modifier"] }
    let units = Array(text.utf16)
    var offset = 0
    var posted = false
    while offset < units.count {
      guard AXIsProcessTrusted(), CGPreflightPostEventAccess(),
            focusedTarget().map({ sameTarget(target, $0) }) == true,
            !hasHeldModifier() else {
        return ["status": posted ? "partial" : "rejected", "reason": "target_or_permission_changed"]
      }
      let end = min(offset + 16, units.count)
      var safeEnd = end
      if safeEnd < units.count, safeEnd > offset,
         (0xD800...0xDBFF).contains(units[safeEnd - 1]) {
        safeEnd -= 1
      }
      let chunk = Array(units[offset..<safeEnd])
      guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
        return ["status": posted ? "partial" : "rejected", "reason": "event_creation_failed"]
      }
      chunk.withUnsafeBufferPointer { buffer in
        down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
        up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
      }
      down.flags = []
      up.flags = []
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      posted = true
      offset = safeEnd
    }
    guard focusedTarget().map({ sameTarget(target, $0) }) == true else {
      return ["status": "partial", "reason": "foreground_window_changed"]
    }
    return ["status": "submitted", "reason": "all_events_posted"]
  }

  private static func focusedTarget() -> FocusedTarget? {
    let system = AXUIElementCreateSystemWide()
    var appValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
          let appValue, CFGetTypeID(appValue) == AXUIElementGetTypeID() else { return nil }
    let app = unsafeBitCast(appValue, to: AXUIElement.self)
    var windowValue: CFTypeRef?
    var elementValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
          AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &elementValue) == .success,
          let windowValue, let elementValue,
          CFGetTypeID(windowValue) == AXUIElementGetTypeID(), CFGetTypeID(elementValue) == AXUIElementGetTypeID() else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(app, &pid) == .success else { return nil }
    return FocusedTarget(pid: pid, window: unsafeBitCast(windowValue, to: AXUIElement.self), element: unsafeBitCast(elementValue, to: AXUIElement.self))
  }

  private static func sameTarget(_ lhs: FocusedTarget, _ rhs: FocusedTarget) -> Bool {
    lhs.pid == rhs.pid && CFEqual(lhs.window, rhs.window) && CFEqual(lhs.element, rhs.element)
  }

  private static func hasHeldModifier() -> Bool {
    let flags = CGEventSource.flagsState(.combinedSessionState)
    return flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) || flags.contains(.maskShift)
  }

  private static func isUnsupportedControl(_ scalar: UnicodeScalar) -> Bool {
    scalar.value < 0x20 || (0x7f...0x9f).contains(scalar.value)
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
