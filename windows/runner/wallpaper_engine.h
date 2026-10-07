#pragma once
#include <windows.h>
#include <string>
#include <atomic>
#include <mutex>
#include <future>
#include <thread>
#include <vector>

// System dynamic-desktop engine (Windows). Decodes a video with the OS-built-in
// Media Foundation Source Reader and paints each frame into a WorkerW-injected
// window with GDI (StretchDIBits).
//
// WHY THIS (and not MFPlay / EVR):
//   Media Foundation's EVR (the video presenter used by MFPlay) does NOT reliably
//   present when its host window is reparented into the desktop WorkerW (the
//   layer behind the icons). The result is a window that is visible and injected
//   correctly but shows only the host's background brush ("red screen"). GDI
//   drawing, by contrast, composites through DWM into whatever parent the window
//   has -- including a cross-process WorkerW child -- so the video always shows.
//   No third-party SDK (e.g. VLC) is required; only the Windows SDK ships it.
//
// THREADING MODEL (critical for stability):
//   The window + decode loop run on a DEDICATED background STA thread with its own
//   message pump. The window is WS_EX_NOACTIVATE + HWND_BOTTOM, so it sits behind
//   the desktop icons, never steals focus, and never swallows input (no system
//   freeze). GDI painting does not need an EVR, so WS_EX_TRANSPARENT is NOT used.
class WallpaperEngine {
 public:
  static WallpaperEngine& instance();

  // Whether the current platform is supported (true only on Windows).
  bool isSupported() const;

  // Start the dynamic desktop with the given video file (looping).
  // Returns an empty string on success, or a short diagnostic code on failure
  // (e.g. "no_workerw_parent", "reader_failed:0x...", "ok sp=0/1").
  std::string start(const std::wstring& videoPath);

  // Stop the dynamic desktop and destroy the render window. Also forces the
  // desktop wallpaper to repaint so the original background is restored.
  void stop();

  // Blit the most recently decoded RGB32 frame into the given window. Public so
  // the free RenderWndProc can call it via GWLP_USERDATA.
  void blit(HWND w);

  // Clear the paint-pending flag. Public so the free RenderWndProc can reset it
  // after a WM_PAINT completes, letting drawSample queue the next repaint.
  void clearPaintPending();

 private:
  WallpaperEngine();
  ~WallpaperEngine();
  WallpaperEngine(const WallpaperEngine&) = delete;
  WallpaperEngine& operator=(const WallpaperEngine&) = delete;

  // Make Progman build the WorkerW container (0x052C), then find the real
  // wallpaper WorkerW (the sibling right after the icon WorkerW). Returns the
  // chosen parent HWND (nullptr if none found).
  HWND findWorkerW();

  // Create the render window as a top-level WS_POPUP, then reparent it into the
  // given wallpaper WorkerW. Returns the window HWND, or nullptr on failure.
  HWND createRenderWindow(HWND parent);

  // Entry point of the dedicated decode/paint thread: creates the window, the
  // Source Reader, and runs the frame loop until running_ is false.
  void renderThread();

  // Convert an NV12 media buffer to RGB32 and blit it into the render window.
  void drawSample(/* IMFMediaBuffer* */ void* pBuf, int w, int h, int strideY);

  // Resolve the pending start() with a diagnostic string (called once, from the
  // render thread). Thread-safe.
  void signalReady(const std::string& s);

  // Re-apply the user's current wallpaper so the desktop repaints after we
  // remove our injected window.
  void restoreWallpaper();

  HWND render_hwnd_ = nullptr;  // full-screen render window (injected)
  HWND parent_ = nullptr;       // chosen WorkerW parent
  bool setparent_ok_ = false;   // whether SetParent into WorkerW succeeded
  std::wstring video_path_;
  std::atomic<bool> running_{false};  // gate for the render thread's loop
  std::atomic<bool> paint_pending_{false};  // a WM_PAINT is already queued

  std::thread render_thread_;   // dedicated decode/paint thread
  std::mutex mtx_;              // guards render_hwnd_ handoff

  // Decoded frame kept for WM_PAINT (resize/restore repaints).
  std::vector<BYTE> frame_rgb_;
  int frame_w_ = 0;
  int frame_h_ = 0;
  GUID out_subtype_ = GUID_NULL;  // actual decoded subtype (NV12 / RGB32 / ...)
  std::mutex frame_cs_;

  // Used to hand the decode result from the render thread back to start().
  std::promise<std::string>* ready_prom_ = nullptr;
  std::mutex ready_mux_;
};
