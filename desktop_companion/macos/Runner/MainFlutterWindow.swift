import Cocoa
import FlutterMacOS
import ApplicationServices
import Carbon

enum MacInputPermissions {
  #if LUMIAKEY_TESTFLIGHT
  static let testFlight = true
  #else
  static let testFlight = false
  #endif

  static func canPostPointer(testFlight: Bool, eventPosting: Bool, accessibility: Bool) -> Bool {
    eventPosting && (testFlight || accessibility)
  }

  static var pointerAllowed: Bool {
    canPostPointer(testFlight: testFlight, eventPosting: CGPreflightPostEventAccess(),
                   accessibility: !testFlight && AXIsProcessTrusted())
  }

  static var status: [String: Bool] {
    [
      "testFlight": testFlight,
      "eventPosting": CGPreflightPostEventAccess(),
      "accessibility": !testFlight && AXIsProcessTrusted(),
    ]
  }

  static func request() {
    if !testFlight {
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    _ = CGRequestPostEventAccess()
  }
}

struct MacShortcutChord {
  let keyCode: CGKeyCode
  let flags: CGEventFlags

  static func parse(
    _ keys: [String],
    characterKey: (String) -> (code: CGKeyCode, flags: CGEventFlags)? = layoutKey
  ) -> Self? {
    guard (1...5).contains(keys.count) else { return nil }
    var flags: CGEventFlags = []
    var keyCode: CGKeyCode?
    for key in keys {
      switch key {
      case "CTRL", "CONTROL": flags.insert(.maskControl)
      case "ALT", "OPTION": flags.insert(.maskAlternate)
      case "SHIFT": flags.insert(.maskShift)
      case "META", "COMMAND", "WIN": flags.insert(.maskCommand)
      default:
        guard keyCode == nil else { return nil }
        if let special = specialKeyCodes[key] {
          keyCode = special
        } else if key.utf8.count == 1,
                  "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789[]`/\\-=".contains(key),
                  let character = characterKey(key.lowercased()) {
          keyCode = character.code
          flags.formUnion(character.flags)
        } else {
          return nil
        }
      }
    }
    guard let keyCode else { return nil }
    return Self(keyCode: keyCode, flags: flags)
  }

  private static let specialKeyCodes: [String: CGKeyCode] = [
    "ENTER": 36, "RETURN": 36, "TAB": 48, "SPACE": 49, "BACKSPACE": 51,
    "ESC": 53, "ESCAPE": 53, "DELETE": 117, "HOME": 115, "END": 119,
    "PAGEUP": 116, "PAGEDOWN": 121, "LEFT": 123, "RIGHT": 124, "DOWN": 125, "UP": 126,
    "F1": 122, "F2": 120, "F3": 99, "F4": 118, "F5": 96, "F6": 97,
    "F7": 98, "F8": 100, "F9": 101, "F10": 109, "F11": 103, "F12": 111,
  ]

  // Translate the user's active layout so character shortcuts work on a
  // non-US keyboard without accidentally posting the US physical key.
  static func layoutKey(_ character: String) -> (code: CGKeyCode, flags: CGEventFlags)? {
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let value = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
          let bytes = CFDataGetBytePtr(Unmanaged<CFData>.fromOpaque(value).takeUnretainedValue()) else {
      return nil
    }
    let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
    let variants: [(UInt32, CGEventFlags)] = [
      (0, []),
      (UInt32(shiftKey >> 8), .maskShift),
      (UInt32(optionKey >> 8), .maskAlternate),
      (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate]),
    ]
    for (modifiers, flags) in variants {
      for code in UInt16(0)...UInt16(127) {
        var deadKey: UInt32 = 0
        var length = 0
        var output = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
          layout, code, UInt16(kUCKeyActionDown), modifiers,
          UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
          &deadKey, output.count, &length, &output
        )
        if status == noErr, length > 0,
           String(decoding: output.prefix(length), as: UTF16.self).lowercased() == character {
          return (code, flags)
        }
      }
    }
    return nil
  }

  func events() -> (down: CGEvent, up: CGEvent)? {
    guard let source = CGEventSource(stateID: .privateState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
      return nil
    }
    down.flags = flags
    up.flags = flags
    return (down, up)
  }
}

struct PointerEventFactory {
  static func move(
    from location: CGPoint,
    deltaX: Int,
    deltaY: Int,
    displayBounds: [CGRect]
  ) -> (event: CGEvent, location: CGPoint)? {
    let destination = clampedDestination(
      CGPoint(x: location.x + CGFloat(deltaX), y: location.y + CGFloat(deltaY)),
      displayBounds: displayBounds
    )
    guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: destination, mouseButton: .left) else {
      return nil
    }
    event.setIntegerValueField(.mouseEventDeltaX, value: Int64(deltaX))
    event.setIntegerValueField(.mouseEventDeltaY, value: Int64(deltaY))
    return (event, destination)
  }

  static func clampedDestination(_ target: CGPoint, displayBounds: [CGRect]) -> CGPoint {
    let displays = displayBounds.filter { !$0.isNull && !$0.isEmpty }
    guard !displays.isEmpty else { return target }
    if displays.contains(where: { $0.contains(target) }) { return target }

    let candidates = displays.map { bounds in
      CGPoint(
        x: min(max(target.x, bounds.minX), bounds.maxX.nextDown),
        y: min(max(target.y, bounds.minY), bounds.maxY.nextDown)
      )
    }
    return candidates.min { first, second in
      let firstX = first.x - target.x
      let firstY = first.y - target.y
      let secondX = second.x - target.x
      let secondY = second.y - target.y
      return firstX * firstX + firstY * firstY < secondX * secondX + secondY * secondY
    } ?? target
  }
}

class MainFlutterWindow: NSWindow {
  private var systemControlChannel: FlutterMethodChannel?
  private var dictationChannel: FlutterMethodChannel?
  private var pointerChannel: FlutterMethodChannel?
  private var inputChannel: FlutterMethodChannel?
  private var vibeSystemChannel: FlutterMethodChannel?
  private var appIconChannel: FlutterMethodChannel?
  private var installedAppsChannel: FlutterMethodChannel?
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
    let installedApps = FlutterMethodChannel(
      name: "lumiakeys/installed_apps",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    installedApps.setMethodCallHandler { call, result in
      guard call.method == "launch" || call.method == "icon" else {
        result(FlutterMethodNotImplemented); return
      }
      guard let args = call.arguments as? [String: Any], args.count == 2,
            args["kind"] as? String == "macBundle",
            let path = args["locator"] as? String,
            !path.isEmpty, path.utf8.count <= 16384, path.hasPrefix("/"),
            path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
        result(FlutterError(code: "registered_app_unavailable", message: "The registered application is unavailable.", details: nil)); return
      }
      let url = URL(fileURLWithPath: path)
      guard url.pathExtension == "app", let bundle = Bundle(url: url),
            let executable = bundle.executableURL,
            FileManager.default.isExecutableFile(atPath: executable.path) else {
        result(FlutterError(code: "registered_app_unavailable", message: "The registered application is unavailable.", details: nil)); return
      }
      if call.method == "icon" {
        guard let image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else { result(nil); return }
        image.size = NSSize(width: 128, height: 128)
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
              data.count <= 64 * 1024 else { result(nil); return }
        result(FlutterStandardTypedData(bytes: data)); return
      }
      if #available(macOS 10.15, *) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = []
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
          DispatchQueue.main.async {
            if app != nil && error == nil { result(true) }
            else { result(FlutterError(code: "registered_app_unavailable", message: "The operating system rejected this launch.", details: nil)) }
          }
        }
      } else {
        result(FlutterError(code: "registered_app_unavailable", message: "This macOS version does not support registered application launch.", details: nil))
      }
    }
    installedAppsChannel = installedApps
    let input = FlutterMethodChannel(
      name: "lumiakeys/mac_input",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    input.setMethodCallHandler { call, result in
      switch call.method {
      case "usesTestFlightInput":
        result(MacInputPermissions.testFlight)
      case "frontmostMatches":
        guard let arguments = call.arguments as? [String: Any],
              let appId = arguments["appId"] as? String,
              let app = NSWorkspace.shared.frontmostApplication else {
          result(false)
          return
        }
        result(Self.matchesShortcutApp(appId, bundleId: app.bundleIdentifier, name: app.localizedName))
      case "postShortcut":
        guard MacInputPermissions.testFlight,
              let arguments = call.arguments as? [String: Any],
              let keys = arguments["keys"] as? [String],
              arguments["appId"] == nil || arguments["appId"] is String else {
          result(FlutterError(code: "shortcut_unavailable", message: "The native shortcut route is unavailable.", details: nil))
          return
        }
        result(Self.postShortcut(keys, expectedAppId: arguments["appId"] as? String))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    inputChannel = input

    let channel = FlutterMethodChannel(
      name: "lumiakeys/system_control",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setDark":
        guard let arguments = call.arguments as? [String: Any],
              let enabled = arguments["enabled"] as? Bool else {
          result(FlutterError(code: "invalid_arguments", message: "Missing enabled flag.", details: nil))
          return
        }
        if MacInputPermissions.testFlight, !CGPreflightPostEventAccess() {
          result(Self.eventPermissionError())
          return
        }
        self?.setDark(enabled)
        result(nil)
      case "playPause", "volumeUp", "volumeDown":
        guard CGPreflightPostEventAccess() else {
          result(Self.eventPermissionError())
          return
        }
        guard self?.postAuxiliaryKey(call.method == "volumeUp" ? 0 : (call.method == "volumeDown" ? 1 : 16)) == true else {
          result(FlutterError(code: "media_control_failed", message: "macOS did not create the media key event.", details: nil))
          return
        }
        result(nil)
      case "getOutputMuted", "toggleOutputMute":
        if MacInputPermissions.testFlight {
          result(FlutterError(code: "sandbox_system_control_unavailable", message: "System mute is unavailable in this TestFlight build.", details: nil))
          return
        }
        do {
          let muted = try self?.runVolumeScript(
            call.method == "getOutputMuted"
              ? "return output muted of (get volume settings)"
              : "set volume output muted not (output muted of (get volume settings))\nreturn output muted of (get volume settings)"
          ) ?? false
          result(muted)
        } catch {
          result(FlutterError(code: "system_control_failed", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    systemControlChannel = channel

    let appIcon = FlutterMethodChannel(
      name: "lumiakeys/app_icon",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appIcon.setMethodCallHandler { call, result in
      guard call.method == "get",
            let arguments = call.arguments as? [String: Any],
            let appId = arguments["appId"] as? String,
            let executable = arguments["executable"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "Missing app ID or executable.", details: nil))
        return
      }
      let bundleIds: [String: String] = [
        "codex": "com.openai.codex", "chatgpt": "com.openai.chatgpt",
        "claude": "com.anthropic.claudefordesktop", "cursor": "com.todesktop.230313mzl4w4u92",
        "chrome": "com.google.Chrome", "edge": "com.microsoft.edgemac",
        "firefox": "org.mozilla.firefox", "safari": "com.apple.Safari",
        "teams": "com.microsoft.teams2", "zoom": "us.zoom.xos",
        "photoshop": "com.adobe.Photoshop", "illustrator": "com.adobe.illustrator",
        "vscode": "com.microsoft.VSCode", "premiere": "com.adobe.PremierePro",
        "appleMusic": "com.apple.Music", "finder": "com.apple.finder"
      ]
      guard let bundleId = bundleIds[appId] else { result(nil); return }
      guard executable.utf8.count <= 1024,
            executable.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
        result(nil); return
      }
      let workspace = NSWorkspace.shared
      let appURL = URL(fileURLWithPath: executable)
      let installedURL = (appURL.pathExtension.lowercased() == "app" && FileManager.default.fileExists(atPath: appURL.path))
        ? appURL
        : workspace.urlForApplication(withBundleIdentifier: bundleId)
      guard let installedURL else { result(nil); return }
      guard let image = workspace.icon(forFile: installedURL.path).copy() as? NSImage else { result(nil); return }
      image.size = NSSize(width: 128, height: 128)
      var rect = NSRect(origin: .zero, size: image.size)
      guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
            let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]),
            data.count <= 64 * 1024 else { result(nil); return }
      result(FlutterStandardTypedData(bytes: data))
    }
    appIconChannel = appIcon

    let dictation = FlutterMethodChannel(
      name: "lumiakeys/dictation",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    dictation.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startSystemDictation":
        if MacInputPermissions.testFlight {
          result(FlutterError(code: "dictation_unavailable", message: "System Dictation is unavailable in this build.", details: nil))
          return
        }
        guard AXIsProcessTrusted() else {
          result(FlutterError(code: "accessibility_permission_missing", message: "Allow LumiaKey Desktop in System Settings → Privacy & Security → Accessibility, then try Dictate again.", details: nil))
          return
        }
        guard let target = Self.focusedTarget(),
              target.pid != ProcessInfo.processInfo.processIdentifier,
              Self.matchesChatGpt(pid: target.pid) else {
          result(FlutterError(code: "wrong_foreground_app", message: "Switch to ChatGPT and focus its message field before using Dictate.", details: nil))
          return
        }
        guard Self.startSystemDictation(for: target) else {
          result(FlutterError(code: "dictation_not_ready", message: "Focus an editable ChatGPT message field, then choose Dictate again. macOS Dictation must be enabled in Keyboard settings.", details: nil))
          return
        }
        result(nil)
      case "insertText":
        guard let arguments = call.arguments as? [String: Any],
              let text = arguments["text"] as? String else {
          result(["status": "rejected", "reason": "invalid_arguments"])
          return
        }
        result(Self.insertText(text))
      case "validateTarget":
        if MacInputPermissions.testFlight {
          result(Self.focusVerificationUnavailable)
          return
        }
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
        result(!MacInputPermissions.testFlight && AXIsProcessTrusted() && CGPreflightPostEventAccess())
      case "inputPermissionStatus":
        result(MacInputPermissions.status)
      case "requestInputPermissions":
        MacInputPermissions.request()
        result(MacInputPermissions.status)
      case "requestAccessibilityPermission":
        MacInputPermissions.request()
        result(!MacInputPermissions.testFlight && AXIsProcessTrusted() && CGPreflightPostEventAccess())
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

    let pointer = FlutterMethodChannel(
      name: "lumiakeys/pointer",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    pointer.setMethodCallHandler { call, result in
      guard call.method == "apply",
            let arguments = call.arguments as? [String: Any],
            let inputs = arguments["inputs"] as? [[String: Any]],
            !inputs.isEmpty, inputs.count <= 32 else {
        result(FlutterError(code: "pointer_rejected", message: "Invalid pointer batch", details: nil))
        return
      }
      guard MacInputPermissions.pointerAllowed else {
        result(FlutterError(code: "pointer_permission_missing", message: "Allow LumiaKey Desktop in macOS Accessibility settings", details: nil))
        return
      }
      var pointerLocation = CGEvent(source: nil)?.location ?? .zero
      var displayCount: UInt32 = 0
      _ = CGGetActiveDisplayList(0, nil, &displayCount)
      var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
      _ = CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
      let displayBounds = displayIDs.map { CGDisplayBounds($0) }
      for input in inputs {
        guard let kind = input["kind"] as? String else {
          result(FlutterError(code: "pointer_rejected", message: "Invalid pointer input", details: nil))
          return
        }
        switch kind {
        case "move":
          guard let x = input["x"] as? Int, let y = input["y"] as? Int,
                (-127...127).contains(x), (-127...127).contains(y),
                let movement = PointerEventFactory.move(
                  from: pointerLocation, deltaX: x, deltaY: y,
                  displayBounds: displayBounds
                ) else {
            result(FlutterError(code: "pointer_rejected", message: "Invalid movement", details: nil))
            return
          }
          movement.event.post(tap: .cghidEventTap)
          pointerLocation = movement.location
        case "scroll":
          guard let y = input["y"] as? Int, y != 0, (-127...127).contains(y),
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                    wheelCount: 1, wheel1: Int32(y * 10),
                                    wheel2: 0, wheel3: 0) else {
            result(FlutterError(code: "pointer_rejected", message: "Invalid scroll", details: nil))
            return
          }
          event.location = pointerLocation
          event.post(tap: .cghidEventTap)
        case "button":
          guard let secondary = input["secondary"] as? Bool else {
            result(FlutterError(code: "pointer_rejected", message: "Invalid button", details: nil))
            return
          }
          let button: CGMouseButton = secondary ? .right : .left
          let down: CGEventType = secondary ? .rightMouseDown : .leftMouseDown
          let up: CGEventType = secondary ? .rightMouseUp : .leftMouseUp
          let location = pointerLocation
          guard let downEvent = CGEvent(mouseEventSource: nil, mouseType: down,
                                        mouseCursorPosition: location, mouseButton: button),
                let upEvent = CGEvent(mouseEventSource: nil, mouseType: up,
                                      mouseCursorPosition: location, mouseButton: button) else {
            result(FlutterError(code: "pointer_rejected", message: "Could not create button event", details: nil))
            return
          }
          downEvent.post(tap: .cghidEventTap)
          upEvent.post(tap: .cghidEventTap)
        default:
          result(FlutterError(code: "pointer_rejected", message: "Unsupported pointer input", details: nil))
          return
        }
      }
      result(nil)
    }
    pointerChannel = pointer

    let vibeSystem = FlutterMethodChannel(
      name: "lumiakeys/vibe_system_tools",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    vibeSystem.setMethodCallHandler { call, result in
      guard call.method == "execute",
            let arguments = call.arguments as? [String: Any],
            let appId = arguments["appId"] as? String,
            let actionId = arguments["actionId"] as? String else {
        result(["status": "rejected", "reason": "invalid_arguments"])
        return
      }
      result(Self.executeVibeSystemAction(appId: appId, actionId: actionId))
    }
    vibeSystemChannel = vibeSystem

    super.awakeFromNib()
  }

  private static let focusVerificationUnavailable = [
    "status": "rejected",
    "reason": "focus_verification_unavailable",
  ]

  private static func eventPermissionError() -> FlutterError {
    FlutterError(code: "event_permission_missing",
                 message: "Grant LumiaKey permission to send keyboard and mouse events in System Settings, then retry.",
                 details: nil)
  }

  static func matchesShortcutApp(_ appId: String, bundleId: String?, name: String? = nil) -> Bool {
    guard let id = bundleId?.lowercased() else { return false }
    switch appId {
    case "codex": return ["com.openai.codex", "com.openai.chatgpt", "com.openai.chat"].contains(id)
    case "chatgpt":
      return ["com.openai.chatgpt", "com.openai.chat"].contains(id) ||
        (id == "com.openai.codex" && name?.caseInsensitiveCompare("ChatGPT") == .orderedSame)
    case "claude": return id == "com.anthropic.claudefordesktop"
    case "cursor": return id == "com.todesktop.230313mzl4w4u92"
    case "chrome": return id == "com.google.chrome"
    case "edge": return id == "com.microsoft.edgemac"
    case "firefox": return id == "org.mozilla.firefox"
    case "safari": return id == "com.apple.safari"
    case "teams": return ["com.microsoft.teams", "com.microsoft.teams2"].contains(id)
    case "zoom": return id == "us.zoom.xos"
    case "photoshop": return id == "com.adobe.photoshop"
    case "illustrator": return id == "com.adobe.illustrator"
    case "vscode": return id == "com.microsoft.vscode"
    case "premiere": return id == "com.adobe.premierepro"
    case "appleMusic": return id == "com.apple.music"
    case "finder": return id == "com.apple.finder"
    default: return false
    }
  }

  private static func postShortcut(_ keys: [String], expectedAppId: String?) -> FlutterError? {
    guard CGPreflightPostEventAccess() else { return eventPermissionError() }
    guard let chord = MacShortcutChord.parse(keys), let events = chord.events() else {
      return FlutterError(code: "shortcut_rejected", message: "The shortcut is unavailable on the active keyboard layout.", details: nil)
    }
    if let expectedAppId {
      guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier > 0,
            matchesShortcutApp(expectedAppId, bundleId: app.bundleIdentifier, name: app.localizedName) else {
        return FlutterError(code: "wrong_foreground_app", message: "Switch to the selected app before using this shortcut.", details: nil)
      }
      events.down.postToPid(app.processIdentifier)
      events.up.postToPid(app.processIdentifier)
    } else {
      events.down.post(tap: .cghidEventTap)
      events.up.post(tap: .cghidEventTap)
    }
    return nil
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

  private static func matchesChatGpt(pid: pid_t) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
    return matchesShortcutApp(
      "chatgpt",
      bundleId: app.bundleIdentifier,
      name: app.localizedName
    )
  }

  private static func startSystemDictation(for target: FocusedTarget) -> Bool {
    guard focusedTarget().map({ sameTarget(target, $0) }) == true,
          matchesChatGpt(pid: target.pid) else { return false }
    let app = AXUIElementCreateApplication(target.pid)
    var menuBarValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
          let menuBarValue, CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else { return false }
    let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
    guard let editMenu = findMenuItem(
      in: menuBar,
      titles: ["edit", "编辑", "編輯"],
      role: kAXMenuBarItemRole as String,
      depth: 0
    ),
    let dictationItem = findMenuItem(
      in: editMenu,
      titles: ["start dictation", "开始听写", "開始聽寫"],
      role: kAXMenuItemRole as String,
      depth: 0
    ) else { return false }
    var enabledValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(dictationItem, kAXEnabledAttribute as CFString, &enabledValue) == .success,
          (enabledValue as? Bool) == true,
          focusedTarget().map({ sameTarget(target, $0) }) == true,
          matchesChatGpt(pid: target.pid) else { return false }
    return AXUIElementPerformAction(dictationItem, kAXPressAction as CFString) == .success
  }

  private static func findMenuItem(
    in element: AXUIElement,
    titles: Set<String>,
    role expectedRole: String,
    depth: Int
  ) -> AXUIElement? {
    guard depth < 8 else { return nil }
    var roleValue: CFTypeRef?
    var titleValue: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
    _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
    let role = roleValue as? String ?? ""
    var title = (titleValue as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if title.hasSuffix("…") { title.removeLast() }
    if title.hasSuffix("...") { title.removeLast(3) }
    title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if role == expectedRole, titles.contains(title) { return element }
    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement] else { return nil }
    for child in children {
      if let match = findMenuItem(
        in: child,
        titles: titles,
        role: expectedRole,
        depth: depth + 1
      ) { return match }
    }
    return nil
  }

  private static func insertText(
    _ text: String,
    expectedAppId: String? = nil,
    moveCaretLeft: Bool = false
  ) -> [String: String] {
    if MacInputPermissions.testFlight { return focusVerificationUnavailable }
    guard AXIsProcessTrusted() else { return ["status": "rejected", "reason": "accessibility_permission_missing"] }
    guard CGPreflightPostEventAccess() else { return ["status": "rejected", "reason": "event_permission_missing"] }
    guard !text.isEmpty, text.utf16.count <= 8000 else { return ["status": "rejected", "reason": text.isEmpty ? "empty_text" : "text_too_long"] }
    guard text.unicodeScalars.allSatisfy({ !isUnsupportedControl($0) }) else { return ["status": "rejected", "reason": "unsupported_control_character"] }
    guard let target = focusedTarget(), target.pid != ProcessInfo.processInfo.processIdentifier else {
      return ["status": "rejected", "reason": "own_or_invalid_foreground"]
    }
    if let expectedAppId, !matchesVibeApp(expectedAppId, pid: target.pid) {
      return ["status": "rejected", "reason": "wrong_foreground_app"]
    }
    guard !hasHeldModifier() else { return ["status": "rejected", "reason": "held_modifier"] }
    let units = Array(text.utf16)
    var offset = 0
    var posted = false
    while offset < units.count {
      guard AXIsProcessTrusted(), CGPreflightPostEventAccess(),
            focusedTarget().map({ sameTarget(target, $0) }) == true,
            expectedAppId.map({ matchesVibeApp($0, pid: target.pid) }) ?? true,
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
    if moveCaretLeft {
      guard expectedAppId.map({ matchesVibeApp($0, pid: target.pid) }) ?? true,
            !hasHeldModifier(),
            let down = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_LeftArrow), keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_LeftArrow), keyDown: false) else {
        return ["status": "partial", "reason": "caret_move_rejected"]
      }
      down.flags = []
      up.flags = []
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
    }
    return ["status": "submitted", "reason": "all_events_posted"]
  }

  private static func executeVibeSystemAction(appId: String, actionId: String) -> [String: String] {
    guard ["codex", "claude", "cursor"].contains(appId) else {
      return ["status": "rejected", "reason": "unsupported_app"]
    }
    guard ["comma", "period", "exclamation", "quote", "screenshot"].contains(actionId) else {
      return ["status": "rejected", "reason": "unsupported_action"]
    }
    if MacInputPermissions.testFlight {
      guard actionId == "screenshot" else { return focusVerificationUnavailable }
      guard let app = NSWorkspace.shared.frontmostApplication,
            matchesShortcutApp(appId, bundleId: app.bundleIdentifier, name: app.localizedName),
            !hasHeldModifier() else {
        return ["status": "rejected", "reason": "foreground_changed_or_modifier_held"]
      }
      guard CGPreflightScreenCaptureAccess() else {
        return ["status": "rejected", "reason": "screen_capture_permission_missing"]
      }
      return launchRegionScreenshot()
    }
    guard let target = focusedTarget(), target.pid != ProcessInfo.processInfo.processIdentifier else {
      return ["status": "rejected", "reason": "own_or_invalid_foreground"]
    }
    guard matchesVibeApp(appId, pid: target.pid) else {
      return ["status": "rejected", "reason": "wrong_foreground_app"]
    }
    guard !hasHeldModifier() else {
      return ["status": "rejected", "reason": "held_modifier"]
    }
    if actionId == "screenshot" {
      guard focusedTarget().map({ sameTarget(target, $0) }) == true,
            matchesVibeApp(appId, pid: target.pid),
            !hasHeldModifier() else {
        return ["status": "rejected", "reason": "foreground_changed_or_modifier_held"]
      }
      return launchRegionScreenshot()
    }
    let text: String
    switch actionId {
    case "comma": text = "，"
    case "period": text = "。"
    case "exclamation": text = "！"
    default: text = "「」"
    }
    let insertion = insertText(text, expectedAppId: appId, moveCaretLeft: actionId == "quote")
    if insertion["status"] == "submitted" {
      return ["status": "delivered"]
    }
    return insertion
  }

  private static func launchRegionScreenshot() -> [String: String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-i", "-c"]
    do {
      try process.run()
      return ["status": "launched"]
    } catch {
      return ["status": "rejected", "reason": "screenshot_launch_failed"]
    }
  }

  private static func matchesVibeApp(_ expectedAppId: String, pid: pid_t) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: pid),
          let executable = app.executableURL?.deletingPathExtension().lastPathComponent.lowercased() else {
      return false
    }
    switch expectedAppId {
    case "codex": return executable == "codex" || executable == "chatgpt"
    case "claude": return executable == "claude"
    case "cursor": return executable == "cursor"
    default: return false
    }
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

  private func runVolumeScript(_ source: String) throws -> Bool {
    guard let script = NSAppleScript(source: source) else {
      throw NSError(domain: "LumiaKeySystemControl", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create the system volume request."])
    }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    if let error {
      throw NSError(domain: "LumiaKeySystemControl", code: 2, userInfo: [NSLocalizedDescriptionKey: error[NSAppleScript.errorMessage] as? String ?? "Could not read or change system mute state."])
    }
    return result.booleanValue
  }

  @discardableResult
  private func postAuxiliaryKey(_ keyType: Int32) -> Bool {
    let down = postAuxiliaryKey(keyType, keyState: 0xA)
    let up = postAuxiliaryKey(keyType, keyState: 0xB)
    Thread.sleep(forTimeInterval: 0.01)
    return down && up
  }

  @discardableResult
  private func postAuxiliaryKey(_ keyType: Int32, keyState: Int) -> Bool {
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
    guard let cgEvent = event?.cgEvent else { return false }
    cgEvent.post(tap: .cghidEventTap)
    return true
  }
}
