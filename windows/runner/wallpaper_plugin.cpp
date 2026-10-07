// Dynamic-desktop MethodChannel host implementation.
// Video decoding uses the OS-built-in Media Foundation Source Reader + GDI
// Windows SDK); no third-party SDK is required. Prerequisites on the build
// machine (just Visual Studio + Windows SDK):
//   1) windows/runner/CMakeLists.txt already compiles wallpaper_engine.cpp and
//      wallpaper_plugin.cpp
//   2) flutter_window.cpp already includes "wallpaper_plugin.h" and calls
//      RegisterWallpaperPlugin(flutter_controller_->engine()) inside OnCreate
#include "wallpaper_engine.h"
#include "wallpaper_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <memory>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;
using flutter::MethodChannel;

std::wstring Utf8ToWstring(const std::string& s) {
  if (s.empty()) return {};
  int need = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring out(need, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &out[0], need);
  if (!out.empty() && out.back() == L'\0') out.pop_back();
  return out;
}

void OnWallpaperMethodCall(const MethodCall<>& call,
                           std::unique_ptr<MethodResult<>> result,
                           flutter::FlutterEngine* engine) {
  const auto& method = call.method_name();
  auto& wallpaper = WallpaperEngine::instance();
  if (method == "isSupported") {
    // MethodResult::Success only accepts an EncodableValue; wrap the bool.
    result->Success(EncodableValue(wallpaper.isSupported()));
  } else if (method == "start") {
    std::wstring path;
    if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
      auto it = args->find(EncodableValue("path"));
      if (it != args->end()) {
        if (const auto* v = std::get_if<std::string>(&it->second)) {
          path = Utf8ToWstring(*v);
        }
      }
    }
    result->Success(EncodableValue(wallpaper.start(path)));
  } else if (method == "stop") {
    wallpaper.stop();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void RegisterWallpaperPlugin(flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<MethodChannel<>>(
      engine->messenger(), "olivia/wallpaper",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [engine](const MethodCall<>& call,
               std::unique_ptr<MethodResult<>> result) {
        OnWallpaperMethodCall(call, std::move(result), engine);
      });
}
