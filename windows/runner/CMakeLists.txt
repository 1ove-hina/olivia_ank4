cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "wallpaper_engine.cpp"
  "wallpaper_plugin.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Treat all source files as UTF-8 so MSVC does not emit C4819 on non-ASCII
# characters under a non-UTF-8 system code page (e.g. 936/GBK).
target_compile_options(${BINARY_NAME} PRIVATE /utf-8)

# Copy the tray icon next to the executable so tray_manager can load it at
# runtime (tray_manager needs a file path, not a compiled resource). The app
# icon (resources/app_icon.ico) is reused as the tray icon under the name
# tray_icon.ico. POST_BUILD covers both Debug (flutter run) and Release
# (flutter build windows) output directories.
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/resources/app_icon.ico"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/tray_icon.ico"
  COMMENT "Copying tray icon (tray_icon.ico) next to executable"
)

# ---- Dynamic desktop (Olivia wallpaper engine) ----
# Video decoding uses the OS-built-in Media Foundation / MFPlay (shipped with
# the Windows SDK). Linking is done via #pragma comment(lib, ...) inside
# wallpaper_engine.cpp, so no extra include/lib configuration is needed here.

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
