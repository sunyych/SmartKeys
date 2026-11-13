#include "flutter_window.h"

#include <algorithm>
#include <optional>
#include <string>
#include <cwctype>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include <shellapi.h>

#pragma comment(lib, "Shell32.lib")

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

EncodableValue ApplyPointerInputs(const EncodableMap* arguments) {
  if (!arguments) return EncodableValue(false);
  const auto found = arguments->find(EncodableValue("inputs"));
  if (found == arguments->end()) return EncodableValue(false);
  const auto* inputs = std::get_if<flutter::EncodableList>(&found->second);
  if (!inputs || inputs->empty() || inputs->size() > 32) return EncodableValue(false);
  std::vector<INPUT> events;
  for (const auto& value : *inputs) {
    const auto* item = std::get_if<EncodableMap>(&value);
    if (!item) return EncodableValue(false);
    const auto kindIt = item->find(EncodableValue("kind"));
    if (kindIt == item->end()) return EncodableValue(false);
    const auto* kind = std::get_if<std::string>(&kindIt->second);
    if (!kind) return EncodableValue(false);
    INPUT input{};
    input.type = INPUT_MOUSE;
    if (*kind == "move" || *kind == "scroll") {
      const auto yIt = item->find(EncodableValue("y"));
      if (yIt == item->end()) return EncodableValue(false);
      const auto* y = std::get_if<int32_t>(&yIt->second);
      if (!y || *y < -127 || *y > 127) return EncodableValue(false);
      if (*kind == "move") {
        const auto xIt = item->find(EncodableValue("x"));
        if (xIt == item->end()) return EncodableValue(false);
        const auto* x = std::get_if<int32_t>(&xIt->second);
        if (!x || *x < -127 || *x > 127) return EncodableValue(false);
        input.mi.dx = *x;
        input.mi.dy = *y;
        input.mi.dwFlags = MOUSEEVENTF_MOVE;
        events.push_back(input);
      } else {
        input.mi.mouseData = static_cast<DWORD>(*y * WHEEL_DELTA);
        input.mi.dwFlags = MOUSEEVENTF_WHEEL;
        events.push_back(input);
      }
    } else if (*kind == "button") {
      const auto secondaryIt = item->find(EncodableValue("secondary"));
      if (secondaryIt == item->end()) return EncodableValue(false);
      const auto* secondary = std::get_if<bool>(&secondaryIt->second);
      if (!secondary) return EncodableValue(false);
      INPUT down{};
      down.type = INPUT_MOUSE;
      down.mi.dwFlags = *secondary ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
      INPUT up = down;
      up.mi.dwFlags = *secondary ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP;
      events.push_back(down);
      events.push_back(up);
    } else {
      return EncodableValue(false);
    }
  }
  return EncodableValue(SendInput(static_cast<UINT>(events.size()), events.data(), sizeof(INPUT)) == events.size());
}

std::wstring ForegroundExecutable(HWND target) {
  DWORD process = 0;
  GetWindowThreadProcessId(target, &process);
  if (!process) return {};
  HANDLE handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process);
  if (!handle) return {};
  std::wstring path(32768, L'\0');
  DWORD length = static_cast<DWORD>(path.size());
  const BOOL queried = QueryFullProcessImageNameW(handle, 0, path.data(), &length);
  CloseHandle(handle);
  if (!queried || length == 0) return {};
  path.resize(length);
  const size_t slash = path.find_last_of(L"\\/");
  std::wstring name = slash == std::wstring::npos ? path : path.substr(slash + 1);
  std::transform(name.begin(), name.end(), name.begin(),
                 [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return name;
}

bool ForegroundMatchesVibeApp(HWND target, const std::string& app_id) {
  const std::wstring executable = ForegroundExecutable(target);
  if (app_id == "codex") return executable == L"codex.exe" || executable == L"chatgpt.exe";
  if (app_id == "claude") return executable == L"claude.exe";
  if (app_id == "cursor") return executable == L"cursor.exe";
  return false;
}

EncodableValue InsertUnicode(const EncodableMap* arguments,
                             const std::string* expected_app_id = nullptr,
                             bool move_caret_left = false) {
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
  if (expected_app_id && !ForegroundMatchesVibeApp(target, *expected_app_id))
    return DictationResult("rejected", "wrong_foreground_app");
  if (ModifierHeld()) return DictationResult("rejected", "modifier_key_held");
  std::vector<INPUT> inputs;
  inputs.reserve(wide.size() * 2 + (move_caret_left ? 2 : 0));
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
  if (move_caret_left) {
    INPUT left_down{};
    left_down.type = INPUT_KEYBOARD;
    left_down.ki.wVk = VK_LEFT;
    inputs.push_back(left_down);
    INPUT left_up = left_down;
    left_up.ki.dwFlags = KEYEVENTF_KEYUP;
    inputs.push_back(left_up);
  }
  if (GetForegroundWindow() != target || ModifierHeld() ||
      (expected_app_id && !ForegroundMatchesVibeApp(target, *expected_app_id)))
    return DictationResult("rejected", "foreground_changed_or_modifier_held");
  const UINT requested = static_cast<UINT>(inputs.size());
  const UINT inserted = SendInput(requested, inputs.data(), sizeof(INPUT));
  if (inserted == requested) return DictationResult("delivered");
  return inserted == 0 ? DictationResult("rejected", "input_injection_blocked")
                       : DictationResult("partial", "partial_injection");
}

EncodableValue ExecuteVibeSystemAction(const EncodableMap* arguments) {
  if (!arguments) return DictationResult("rejected", "invalid_arguments");
  const auto app = arguments->find(EncodableValue("appId"));
  const auto action = arguments->find(EncodableValue("actionId"));
  if (app == arguments->end() || action == arguments->end())
    return DictationResult("rejected", "missing_action_arguments");
  const auto* app_id = std::get_if<std::string>(&app->second);
  const auto* action_id = std::get_if<std::string>(&action->second);
  if (!app_id || !action_id) return DictationResult("rejected", "invalid_action_arguments");
  if (*app_id != "codex" && *app_id != "claude" && *app_id != "cursor")
    return DictationResult("rejected", "unsupported_app");
  if (*action_id != "comma" && *action_id != "period" &&
      *action_id != "exclamation" && *action_id != "quote" &&
      *action_id != "screenshot")
    return DictationResult("rejected", "unsupported_action");
  const HWND target = GetForegroundWindow();
  if (!target || IsIconic(target)) return DictationResult("rejected", "no_foreground_window");
  if (!ForegroundMatchesVibeApp(target, *app_id))
    return DictationResult("rejected", "wrong_foreground_app");
  if (ModifierHeld()) return DictationResult("rejected", "modifier_key_held");
  if (*action_id == "screenshot") {
    if (GetForegroundWindow() != target ||
        !ForegroundMatchesVibeApp(target, *app_id) || ModifierHeld())
      return DictationResult("rejected", "foreground_changed_or_modifier_held");
    const auto launched = reinterpret_cast<INT_PTR>(
        ShellExecuteW(nullptr, L"open", L"ms-screenclip:", nullptr, nullptr,
                      SW_SHOWNORMAL));
    if (launched <= 32)
      return DictationResult("rejected", "screenshot_launch_failed");
    return DictationResult("launched");
  }
  const char* text = *action_id == "comma" ? "\xEF\xBC\x8C" :
                     *action_id == "period" ? "\xE3\x80\x82" :
                     *action_id == "exclamation" ? "\xEF\xBC\x81" :
                     "\xE3\x80\x8C\xE3\x80\x8D";
  EncodableMap insert_arguments;
  insert_arguments[EncodableValue("text")] = EncodableValue(text);
  return InsertUnicode(&insert_arguments, app_id, *action_id == "quote");
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

  pointer_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "lumiakeys/pointer",
      &flutter::StandardMethodCodec::GetInstance());
  pointer_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "apply") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        const auto applied = ApplyPointerInputs(args);
        if (const auto* success = std::get_if<bool>(&applied); success && *success) {
          result->Success();
        } else {
          result->Error("pointer_rejected", "Pointer input was rejected", nullptr);
        }
      });

  vibe_system_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "lumiakeys/vibe_system_tools",
      &flutter::StandardMethodCodec::GetInstance());
  vibe_system_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "execute") {
          const auto* args = std::get_if<EncodableMap>(call.arguments());
          result->Success(ExecuteVibeSystemAction(args));
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
  pointer_channel_.reset();
  vibe_system_channel_.reset();
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
