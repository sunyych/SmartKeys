#include "installed_apps.h"
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <string>
#include <vector>

#pragma comment(lib, "Shell32.lib")
#pragma comment(lib, "windowscodecs.lib")
namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

bool Utf16(const std::string& input, std::wstring* output) {
  if (input.empty() || input.size() > 16384 || std::any_of(input.begin(), input.end(), [](unsigned char c) { return c < 32 || c == 127; })) return false;
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()), nullptr, 0);
  if (length <= 0) return false;
  output->resize(length);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()), output->data(), length) == length;
}
bool ReadTarget(const EncodableValue* arguments, std::wstring* parsing_name) {
  const auto* map = arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
  if (!map || map->size() != 2) return false;
  const auto kind_item = map->find(EncodableValue("kind"));
  const auto path_item = map->find(EncodableValue("locator"));
  if (kind_item == map->end() || path_item == map->end()) return false;
  const auto* kind = std::get_if<std::string>(&kind_item->second);
  const auto* path = std::get_if<std::string>(&path_item->second);
  if (!kind || !path || !Utf16(*path, parsing_name)) return false;
  if (*kind == "windowsAppId") {
    *parsing_name = L"shell:AppsFolder\\" + *parsing_name;
  } else if (*kind == "windowsShortcut" || *kind == "windowsExecutable") {
    const std::filesystem::path file(*parsing_name);
    std::wstring extension = file.extension().wstring();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
    if (!file.is_absolute() || extension != (*kind == "windowsShortcut" ? L".lnk" : L".exe")) return false;
    const DWORD attrs = GetFileAttributesW(parsing_name->c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0) return false;
  } else return false;
  // Resolve the exact registered Shell item before either launch or icon lookup.
  ComPtr<IShellItem> item;
  return SUCCEEDED(SHCreateItemFromParsingName(parsing_name->c_str(), nullptr, IID_PPV_ARGS(item.GetAddressOf())));
}

std::vector<uint8_t> ReadIcon(const std::wstring& parsing_name) {
  ComPtr<IShellItemImageFactory> shell;
  if (FAILED(SHCreateItemFromParsingName(parsing_name.c_str(), nullptr, IID_PPV_ARGS(shell.GetAddressOf())))) return {};
  HBITMAP handle = nullptr;
  if (FAILED(shell->GetImage(SIZE{128, 128}, SIIGBF_ICONONLY, &handle)) || !handle) return {};
  struct BitmapOwner { HBITMAP value; ~BitmapOwner() { DeleteObject(value); } } bitmap_owner{handle};
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(factory.GetAddressOf())))) return {};
  ComPtr<IWICBitmap> bitmap;
  if (FAILED(factory->CreateBitmapFromHBITMAP(handle, nullptr, WICBitmapUsePremultipliedAlpha, bitmap.GetAddressOf()))) return {};
  UINT width = 0, height = 0;
  if (FAILED(bitmap->GetSize(&width, &height)) || width == 0 || height == 0 || width > 512 || height > 512) return {};
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(converter.GetAddressOf())) || FAILED(converter->Initialize(bitmap.Get(), GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom))) return {};
  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, stream.GetAddressOf()))) return {};
  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, encoder.GetAddressOf())) || FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) return {};
  ComPtr<IWICBitmapFrameEncode> frame;
  if (FAILED(encoder->CreateNewFrame(frame.GetAddressOf(), nullptr)) || FAILED(frame->Initialize(nullptr)) || FAILED(frame->SetSize(width, height))) return {};
  WICPixelFormatGUID pixel_format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(frame->SetPixelFormat(&pixel_format)) || FAILED(frame->WriteSource(converter.Get(), nullptr)) || FAILED(frame->Commit()) || FAILED(encoder->Commit())) return {};
  STATSTG stats{};
  if (FAILED(stream->Stat(&stats, STATFLAG_NONAME)) || stats.cbSize.HighPart != 0 || stats.cbSize.LowPart == 0 || stats.cbSize.LowPart > 64 * 1024) return {};
  LARGE_INTEGER start{};
  if (FAILED(stream->Seek(start, STREAM_SEEK_SET, nullptr))) return {};
  std::vector<uint8_t> result(stats.cbSize.LowPart);
  ULONG read = 0;
  if (FAILED(stream->Read(result.data(), static_cast<ULONG>(result.size()), &read)) || read != result.size()) return {};
  return result;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>> CreateInstalledAppsChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "lumiakeys/installed_apps", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
    if (call.method_name() != "launch" && call.method_name() != "icon") { result->NotImplemented(); return; }
    std::wstring parsing_name;
    if (!ReadTarget(call.arguments(), &parsing_name)) { result->Error("registered_app_unavailable", "The registered application is unavailable."); return; }
    if (call.method_name() == "icon") {
      auto bytes = ReadIcon(parsing_name);
      if (bytes.empty()) result->Success(); else result->Success(EncodableValue(bytes));
      return;
    }
    SHELLEXECUTEINFOW info{};
    info.cbSize = sizeof(info);
    info.fMask = SEE_MASK_FLAG_NO_UI;
    info.lpVerb = L"open";
    info.lpFile = parsing_name.c_str();
    info.lpParameters = nullptr;  // No mobile or custom command-line arguments.
    info.nShow = SW_SHOWNORMAL;
    if (!ShellExecuteExW(&info)) result->Error("registered_app_unavailable", "The operating system rejected this launch.");
    else result->Success(EncodableValue(true));
  });
  return channel;
}
