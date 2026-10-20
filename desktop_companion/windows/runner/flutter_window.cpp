#include "flutter_window.h"

#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {
using EncodableValue = flutter::EncodableValue;
using EncodableMap = flutter::EncodableMap;
constexpr int kToggleHotkeyId = 0x4C4B;

EncodableValue DictationResult(const char* status, const char* reason = nullptr) {
  EncodableMap result;
  result[EncodableValue("status")] = EncodableValue(status);
  if (reason) result[EncodableValue("reason")] = EncodableValue(reason);
  return EncodableValue(result);
}

bool ModifierHeld() {
  return (GetAsyncKeyState(VK_SHIFT) & 0x8000) ||
         (GetAsyncKeyState(VK_CONTROL) & 0x8000) ||
         (GetAsyncKeyState(VK_MENU) & 0x8000) ||
         (GetAsyncKeyState(VK_LWIN) & 0x8000) ||
         (GetAsyncKeyState(VK_RWIN) & 0x8000);
}

EncodableValue InsertUnicode(const EncodableMap* arguments) {
  if (!arguments) return DictationResult("rejected", "invalid_arguments");
  const auto found = arguments->find(EncodableValue("text"));
  if (found == arguments->end()) return DictationResult("rejected", "missing_text");
  const auto* text = std::get_if<std::string>(&found->second);
  if (!text || text->empty()) return DictationResult("rejected", "invalid_text");
  if (text->size() > 32000) return DictationResult("rejected", "text_too_long");
  const int input_size = static_cast<int>(text->size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        text->data(), input_size, nullptr, 0);
  if (count <= 0) return DictationResult("rejected", "invalid_utf8");
  std::wstring wide(count, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(), input_size,
                          wide.data(), count) != count)
    return DictationResult("rejected", "invalid_utf8");
  if (wide.size() > 8000) return DictationResult("rejected", "text_too_long");
  for (size_t i = 0; i < wide.size(); ++i) {
    const wchar_t c = wide[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= wide.size() || wide[i + 1] < 0xDC00 || wide[i + 1] > 0xDFFF)
        return DictationResult("rejected", "invalid_unicode");
      ++i;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      return DictationResult("rejected", "invalid_unicode");
    }
    if (c < 0x20 || (c >= 0x7F && c <= 0x9F))
      return DictationResult("rejected", "unsupported_control_character");
  }
  const HWND target = GetForegroundWindow();
  DWORD process = 0;
  if (!target || IsIconic(target)) return DictationResult("rejected", "no_foreground_window");
  GetWindowThreadProcessId(target, &process);
  if (!process || process == GetCurrentProcessId())
    return DictationResult("rejected", "own_or_invalid_foreground");
  if (ModifierHeld()) return DictationResult("rejected", "modifier_key_held");
  std::vector<INPUT> inputs;
  inputs.reserve(wide.size() * 2);
  for (const wchar_t c : wide) {
    INPUT down{};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = static_cast<WORD>(c);
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    inputs.push_back(down);
    INPUT up = down;
    up.ki.dwFlags |= KEYEVENTF_KEYUP;
    inputs.push_back(up);
  }
  if (GetForegroundWindow() != target || ModifierHeld())
    return DictationResult("rejected", "foreground_changed_or_modifier_held");
  const UINT requested = static_cast<UINT>(inputs.size());
  const UINT inserted = SendInput(requested, inputs.data(), sizeof(INPUT));
  if (inserted == requested) return DictationResult("delivered");
  return inserted == 0 ? DictationResult("rejected", "input_injection_blocked")
                       : DictationResult("partial", "partial_injection");
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  dictation_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "lumiakeys/dictation",
      &flutter::StandardMethodCodec::GetInstance());
  dictation_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "insertText") {
          const auto* args = std::get_if<EncodableMap>(call.arguments());
          result->Success(InsertUnicode(args));
        } else if (call.method_name() == "validateTarget") {
          const HWND target = GetForegroundWindow();
          DWORD process = 0;
          if (!target || IsIconic(target)) result->Success(DictationResult("rejected", "no_foreground_window"));
          else {
            GetWindowThreadProcessId(target, &process);
            if (!process || process == GetCurrentProcessId()) result->Success(DictationResult("rejected", "own_or_invalid_foreground"));
            else if (ModifierHeld()) result->Success(DictationResult("rejected", "modifier_key_held"));
            else result->Success(DictationResult("ready"));
          }
        } else if (call.method_name() == "modifiersHeld") {
          result->Success(EncodableValue(ModifierHeld()));
        } else if (call.method_name() == "registerToggleHotkey") {
          if (toggle_hotkey_registered_) UnregisterHotKey(GetHandle(), kToggleHotkeyId);
          UINT modifiers = MOD_CONTROL | MOD_SHIFT;
          if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
            const auto value = args->find(EncodableValue("shortcut"));
            if (value != args->end()) {
              const auto* shortcut = std::get_if<std::string>(&value->second);
              if (shortcut && *shortcut == "ctrlAltSpace") modifiers = MOD_CONTROL | MOD_ALT;
              if (shortcut && *shortcut == "altShiftSpace") modifiers = MOD_ALT | MOD_SHIFT;
            }
          }
          if (RegisterHotKey(GetHandle(), kToggleHotkeyId,
                             modifiers | MOD_NOREPEAT, VK_SPACE)) {
            toggle_hotkey_registered_ = true;
            result->Success(EncodableValue(true));
          } else {
            result->Error("hotkey_registration_failed",
                          "Global shortcut is unavailable (error " +
                              std::to_string(GetLastError()) + ")", nullptr);
          }
        } else if (call.method_name() == "unregisterToggleHotkey") {
          if (toggle_hotkey_registered_) UnregisterHotKey(GetHandle(), kToggleHotkeyId);
          toggle_hotkey_registered_ = false;
          result->Success(EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  // LumiaKey starts as a tray application. Dart shows the settings window
  // only after the user selects Open Settings from the tray menu.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (toggle_hotkey_registered_) UnregisterHotKey(GetHandle(), kToggleHotkeyId);
  toggle_hotkey_registered_ = false;
  dictation_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_HOTKEY:
      if (wparam == kToggleHotkeyId && dictation_channel_) {
        dictation_channel_->InvokeMethod("toggleHotkeyPressed",
                                         std::make_unique<EncodableValue>());
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
