#pragma once
#include <flutter/flutter_engine.h>

// Registers the dynamic-desktop MethodChannel ("olivia/wallpaper").
// Call this from windows/runner/flutter_window.cpp inside OnCreate, after the
// controller is created:
//   RegisterWallpaperPlugin(flutter_controller_->engine());
void RegisterWallpaperPlugin(flutter::FlutterEngine* engine);
