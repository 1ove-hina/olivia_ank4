#include "wallpaper_engine.h"

#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <objbase.h>  // CoInitializeEx: COM is required for Media Foundation
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>  // IMFSourceReader
#include <mferror.h>
#include <propvarutil.h>   // PROPVARIANT helpers (seek)
#include <chrono>
#include <thread>
#include <windows.h>

// Media Foundation linking (ships with the Windows SDK; no third-party SDK).
// mfreadwrite.lib : MFCreateSourceReaderFromURL / IMFSourceReader
// mfplat.lib      : MFStartup / MFShutdown / MFCreateMediaType etc.
// mfuuid.lib      : IID_IMFSourceReader and other Media Foundation GUIDs
// ole32.lib       : COM base (CoInitialize/CoUninitialize)
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "gdi32.lib")    // StretchDIBits / GetDC / ReleaseDC
#pragma comment(lib, "user32.lib")   // CreateWindow / SystemParametersInfo
#pragma comment(lib, "advapi32.lib") // RegOpenKeyEx (read wallpaper path)

namespace {
const wchar_t kRenderClass[] = L"OliviaWallpaperRender";

// NV12 (separate Y plane, then interleaved U/V) -> packed RGB32. `uvp` points at
// the chroma plane, which begins after the FULL padded Y height (decoders pad the
// encoded height to a multiple of 16, e.g. 1080 -> 1088) -- NOT the display
// height. Passing the padded offset is what keeps the chroma aligned. Self-
// contained software conversion (no extra MFT), reliable across machines.
void Nv12ToRgb32(const BYTE* yp, const BYTE* uvp, int w, int h, int strideY,
                 BYTE* rgb) {
  for (int y = 0; y < h; ++y) {
    const BYTE* yRow = yp + (size_t)y * strideY;
    const BYTE* uvRow = uvp + (size_t)(y / 2) * strideY;
    BYTE* rgbRow = rgb + (size_t)y * w * 4;
    for (int x = 0; x < w; ++x) {
      const int yv = yRow[x];
      const int u = uvRow[(x / 2) * 2];
      const int v = uvRow[(x / 2) * 2 + 1];
      // ITU-R BT.601 limited-range -> RGB
      int r = yv + ((360 * (v - 128)) >> 8);
      int g = yv - ((88 * (u - 128) + 184 * (v - 128)) >> 8);
      int b = yv + ((455 * (u - 128)) >> 8);
      if (r < 0) r = 0; else if (r > 255) r = 255;
      if (g < 0) g = 0; else if (g > 255) g = 255;
      if (b < 0) b = 0; else if (b > 255) b = 255;
      rgbRow[x * 4] = (BYTE)b;
      rgbRow[x * 4 + 1] = (BYTE)g;
      rgbRow[x * 4 + 2] = (BYTE)r;
      rgbRow[x * 4 + 3] = 0;
    }
  }
}

// I420 / IYUV (fully planar Y, U, V) -> packed RGB32.
void I420ToRgb32(const BYTE* yp, const BYTE* up, const BYTE* vp, int w, int h,
                 int strideY, int strideU, int strideV, BYTE* rgb) {
  for (int y = 0; y < h; ++y) {
    const BYTE* yRow = yp + (size_t)y * strideY;
    const BYTE* uRow = up + (size_t)(y / 2) * strideU;
    const BYTE* vRow = vp + (size_t)(y / 2) * strideV;
    BYTE* rgbRow = rgb + (size_t)y * w * 4;
    for (int x = 0; x < w; ++x) {
      const int yv = yRow[x];
      const int u = uRow[x / 2];
      const int v = vRow[x / 2];
      int r = yv + ((360 * (v - 128)) >> 8);
      int g = yv - ((88 * (u - 128) + 184 * (v - 128)) >> 8);
      int b = yv + ((455 * (u - 128)) >> 8);
      if (r < 0) r = 0; else if (r > 255) r = 255;
      if (g < 0) g = 0; else if (g > 255) g = 255;
      if (b < 0) b = 0; else if (b > 255) b = 255;
      rgbRow[x * 4] = (BYTE)b;
      rgbRow[x * 4 + 1] = (BYTE)g;
      rgbRow[x * 4 + 2] = (BYTE)r;
      rgbRow[x * 4 + 3] = 0;
    }
  }
}

// YUY2 / UYVY (packed 4:2:2) -> RGB32. uyvy selects the byte order.
void Yuy2ToRgb32(const BYTE* p, int w, int h, int stride, BYTE* rgb, bool uyvy) {
  for (int y = 0; y < h; ++y) {
    const BYTE* row = p + (size_t)y * stride;
    BYTE* rgbRow = rgb + (size_t)y * w * 4;
    for (int x = 0; x < w; x += 2) {
      int y0, u, y1, v;
      if (uyvy) {
        u = row[x * 2]; y0 = row[x * 2 + 1]; v = row[x * 2 + 2]; y1 = row[x * 2 + 3];
      } else {
        y0 = row[x * 2]; u = row[x * 2 + 1]; y1 = row[x * 2 + 2]; v = row[x * 2 + 3];
      }
      int r0 = y0 + ((360 * (v - 128)) >> 8);
      int g0 = y0 - ((88 * (u - 128) + 184 * (v - 128)) >> 8);
      int b0 = y0 + ((455 * (u - 128)) >> 8);
      int r1 = y1 + ((360 * (v - 128)) >> 8);
      int g1 = y1 - ((88 * (u - 128) + 184 * (v - 128)) >> 8);
      int b1 = y1 + ((455 * (u - 128)) >> 8);
      auto clamp = [](int c) { return c < 0 ? 0 : (c > 255 ? 255 : c); };
      rgbRow[x * 4] = (BYTE)clamp(b0);
      rgbRow[x * 4 + 1] = (BYTE)clamp(g0);
      rgbRow[x * 4 + 2] = (BYTE)clamp(r0);
      rgbRow[x * 4 + 3] = 0;
      rgbRow[x * 4 + 4] = (BYTE)clamp(b1);
      rgbRow[x * 4 + 5] = (BYTE)clamp(g1);
      rgbRow[x * 4 + 6] = (BYTE)clamp(r1);
      rgbRow[x * 4 + 7] = 0;
    }
  }
}

// Read the Source Reader's current video OUTPUT type: subtype, frame size, and
// Y-plane stride. We use this to feed the converter the format the decoder
// ACTUALLY delivers -- without ever forcing a specific output media type (which
// some decoders reject with MF_E_INVALIDMEDIATYPE = 0xC00D36B4).
void ReadCurrentVideoType(IMFSourceReader* reader, GUID& subtype, int& w, int& h,
                          int& stride) {
  subtype = GUID_NULL;
  w = 0;
  h = 0;
  stride = 0;
  if (!reader) return;
  IMFMediaType* cur = nullptr;
  if (FAILED(reader->GetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                         &cur))) {
    return;
  }
  cur->GetGUID(MF_MT_SUBTYPE, &subtype);
  UINT32 tw = 0, th = 0;
  if (SUCCEEDED(MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &tw, &th))) {
    w = (int)tw;
    h = (int)th;
  }
  UINT32 st = 0;
  if (SUCCEEDED(cur->GetUINT32(MF_MT_DEFAULT_STRIDE, &st)) && st != 0) {
    // Stride may be reported negative (bottom-up); normalize to a positive row
    // pitch for the converter.
    stride = (st & 0x80000000u) ? -(int)st : (int)st;
  }
  cur->Release();
}

// Try to pin a render-friendly UNCOMPRESSED output type so the Source Reader
// inserts a decoder and actually delivers YUV/RGB frames (otherwise it passes
// through the compressed H.264 bytes, which is what produced the earlier
// "fmt=OTHER" + garbled output). Setting ONLY subtype+framesize is frequently
// rejected with MF_E_INVALIDMEDIATYPE (0xC00D36B4); the complete, accepted form
// also carries the interlace mode and pixel aspect ratio. We try NV12 first
// (cheapest to convert), then RGB32/RGB24 (no colorspace math on our side).
// Best-effort: if none pins, ReadCurrentVideoType still reports the native type.
void PinOutputType(IMFSourceReader* reader) {
  if (!reader) return;
  UINT32 tw = 0, th = 0;
  IMFMediaType* cur = nullptr;
  if (SUCCEEDED(reader->GetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                            &cur))) {
    MFGetAttributeSize(cur, MF_MT_FRAME_SIZE, &tw, &th);
    cur->Release();
  }
  if (tw == 0 || th == 0) return;  // cannot build a complete uncompressed type
  const GUID candidates[] = {MFVideoFormat_NV12, MFVideoFormat_RGB32,
                             MFVideoFormat_RGB24};
  for (GUID sub : candidates) {
    IMFMediaType* out = nullptr;
    if (FAILED(MFCreateMediaType(&out))) continue;
    out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    out->SetGUID(MF_MT_SUBTYPE, sub);
    MFSetAttributeSize(out, MF_MT_FRAME_SIZE, tw, th);
    // A "complete" uncompressed type: interlace + pixel aspect ratio are what
    // make SetCurrentMediaType succeed where a bare subtype+size is rejected.
    out->SetUINT32(MF_MT_INTERLACE_MODE, 2 /* MFVideoInterlace_Progressive */);
    MFSetAttributeRatio(out, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    HRESULT hr = reader->SetCurrentMediaType(
        (DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, out);
    out->Release();
    if (SUCCEEDED(hr)) return;
  }
}

// True if the subtype is a COMPRESSED video codec bitstream (not uncompressed
// YUV/RGB). When the Source Reader delivers a compressed subtype, the system has
// NO decoder MFT for that codec (e.g. HEVC/H.265 on a machine without the HEVC
// Video Extensions) -- the bitstream cannot be painted, and feeding it to
// drawSample is exactly what produced the earlier "garbled / 花屏" corruption.
// We detect this and report it clearly instead of crashing or garbling.
bool IsCompressedVideo(const GUID& g) {
  return IsEqualGUID(g, MFVideoFormat_H264) ||
         IsEqualGUID(g, MFVideoFormat_H265) ||
         IsEqualGUID(g, MFVideoFormat_HEVC) ||
         IsEqualGUID(g, MFVideoFormat_MPEG2) ||
         IsEqualGUID(g, MFVideoFormat_MP4V) ||
         IsEqualGUID(g, MFVideoFormat_WMV3) ||
         IsEqualGUID(g, MFVideoFormat_VP80) ||
         IsEqualGUID(g, MFVideoFormat_VP90) ||
         IsEqualGUID(g, MFVideoFormat_AV1);
}

// Short name of a video subtype, for diagnostics in the "ok" string.
const char* SubtypeName(const GUID& g) {
  if (IsEqualGUID(g, MFVideoFormat_NV12)) return "NV12";
  if (IsEqualGUID(g, MFVideoFormat_RGB32)) return "RGB32";
  if (IsEqualGUID(g, MFVideoFormat_RGB24)) return "RGB24";
  if (IsEqualGUID(g, MFVideoFormat_RGB555)) return "RGB555";
  if (IsEqualGUID(g, MFVideoFormat_RGB565)) return "RGB565";
  if (IsEqualGUID(g, MFVideoFormat_I420)) return "I420";
  if (IsEqualGUID(g, MFVideoFormat_YV12)) return "YV12";
  if (IsEqualGUID(g, MFVideoFormat_YUY2)) return "YUY2";
  if (IsEqualGUID(g, MFVideoFormat_UYVY)) return "UYVY";
  if (IsEqualGUID(g, MFVideoFormat_AYUV)) return "AYUV";
  if (IsEqualGUID(g, MFVideoFormat_H264)) return "H264";
  // Fallback: many uncompressed subtypes encode a FOURCC in Data1 (little-endian
  // ASCII). Reveal it so an unknown format shows up literally in the toast.
  unsigned d = g.Data1;
  char a = (char)(d & 0xFF), b = (char)((d >> 8) & 0xFF);
  char c = (char)((d >> 16) & 0xFF), e = (char)((d >> 24) & 0xFF);
  if (isprint((unsigned char)a) && isprint((unsigned char)b) &&
      isprint((unsigned char)c) && isprint((unsigned char)e)) {
    static char s[8];
    snprintf(s, sizeof(s), "%c%c%c%c", a, b, c, e);
    return s;
  }
  return "OTHER";
}

// Render window procedure. Paints the latest decoded frame on WM_PAINT.
LRESULT CALLBACK RenderWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  switch (msg) {
    case WM_PAINT: {
      WallpaperEngine* self =
          reinterpret_cast<WallpaperEngine*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
      PAINTSTRUCT ps;
      BeginPaint(hwnd, &ps);
      if (self) {
        self->blit(hwnd);
        self->clearPaintPending();  // allow the next decoded frame to repaint
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    default:
      return DefWindowProc(hwnd, msg, wp, lp);
  }
}
}  // namespace

WallpaperEngine& WallpaperEngine::instance() {
  static WallpaperEngine inst;
  return inst;
}

bool WallpaperEngine::isSupported() const {
  // This engine is built only for the Windows runner, so the platform is
  // always supported here. (The Dart layer also guards unsupported platforms.)
  return true;
}

WallpaperEngine::WallpaperEngine() {
  // MF/SR require the calling thread inside an initialized COM apartment.
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  MFStartup(MF_VERSION, 0);
}

WallpaperEngine::~WallpaperEngine() {
  stop();
  MFShutdown();
}

void WallpaperEngine::signalReady(const std::string& s) {
  std::lock_guard<std::mutex> lk(ready_mux_);
  if (ready_prom_) {
    ready_prom_->set_value(s);
    ready_prom_ = nullptr;
  }
}

// Make Progman build the WorkerW container (0x052C), then find the wallpaper
// WorkerW. Desktop window tree (after 0x052C):
//   Progman
//     WorkerW  (holds SHELLDLL_DefView -> SysListView32 : the desktop ICONS)
//     WorkerW  (empty wallpaper layer, shuffled by 0x052C)
// The wallpaper layer is the WorkerW that comes RIGHT AFTER the icon WorkerW in
// z-order. This is the proven Lively / Wallpaper-Engine selection; reparenting
// our window into it places the video BEHIND the icons.
HWND WallpaperEngine::findWorkerW() {
  HWND progman = FindWindow(L"Progman", nullptr);
  if (progman) {
    SendMessageTimeout(progman, 0x052C, 0, 0, SMTO_NORMAL, 1000, nullptr);
  }
  HWND iconWorker = nullptr;
  HWND candidate = nullptr;
  while ((candidate = FindWindowEx(nullptr, candidate, L"WorkerW", nullptr)) !=
         nullptr) {
    if (FindWindowEx(candidate, nullptr, L"SHELLDLL_DefView", nullptr)) {
      iconWorker = candidate;
      break;
    }
  }
  HWND worker = nullptr;
  if (iconWorker) {
    worker = FindWindowEx(nullptr, iconWorker, L"WorkerW", nullptr);
  }
  if (!worker) {
    candidate = nullptr;
    while ((candidate = FindWindowEx(nullptr, candidate, L"WorkerW", nullptr)) !=
           nullptr) {
      if (!FindWindowEx(candidate, nullptr, L"SHELLDLL_DefView", nullptr)) {
        worker = candidate;
        break;
      }
    }
  }
  if (!worker) worker = progman;  // last resort
  return worker;
}

HWND WallpaperEngine::createRenderWindow(HWND parent) {
  HINSTANCE hInst = GetModuleHandle(nullptr);
  WNDCLASSEX wc = {sizeof(wc)};
  wc.lpfnWndProc = RenderWndProc;
  wc.hInstance = hInst;
  wc.lpszClassName = kRenderClass;
  // Black base: if a frame is not yet painted the window is black, not red, so a
  // partially-decoded state never looks like an error. Video frames cover it.
  wc.hbrBackground = (HBRUSH)CreateSolidBrush(RGB(0, 0, 0));
  RegisterClassEx(&wc);  // harmless if already registered

  // WS_CLIPCHILDREN: we never create video child windows (GDI paints directly),
  // but it keeps the OS from over-painting the client area under any future
  // child and is harmless here.
  HWND w = CreateWindowEx(
      WS_EX_NOACTIVATE, kRenderClass, L"",
      WS_POPUP | WS_VISIBLE | WS_CLIPCHILDREN, 0, 0,
      GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN), nullptr,
      nullptr, hInst, nullptr);
  if (!w) return nullptr;
  SetWindowLongPtr(w, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  setparent_ok_ = false;
  if (parent) {
    HWND old = SetParent(w, parent);
    setparent_ok_ = (old != nullptr);
    if (!setparent_ok_) {
      HWND progman = FindWindow(L"Progman", nullptr);
      if (progman && progman != parent) {
        old = SetParent(w, progman);
        setparent_ok_ = (old != nullptr);
      }
    }
  }
  // Size the injected child to the PARENT's real client rect (device pixels).
  // Using SM_CXSCREEN/SM_CYSCREEN (logical px) here left the window smaller than
  // the physical screen on DPI-scaled displays, so the original desktop wallpaper
  // showed through at the bottom -- the "green bar" symptom. Covering the parent
  // (WorkerW spans the virtual screen) guarantees full coverage at any DPI.
  RECT prc = {0, 0, 0, 0};
  if (parent && GetClientRect(parent, &prc) && prc.right > 0 && prc.bottom > 0) {
    SetWindowPos(w, HWND_BOTTOM, 0, 0, prc.right, prc.bottom,
                 SWP_NOACTIVATE | SWP_FRAMECHANGED);
  } else {
    int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (vw <= 0) vw = GetSystemMetrics(SM_CXSCREEN);
    if (vh <= 0) vh = GetSystemMetrics(SM_CYSCREEN);
    SetWindowPos(w, HWND_BOTTOM, vx, vy, vw, vh,
                 SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
  return w;
}

void WallpaperEngine::blit(HWND w) {
  if (!w) return;
  std::lock_guard<std::mutex> lk(frame_cs_);
  if (frame_rgb_.empty() || frame_w_ == 0 || frame_h_ == 0) return;
  BITMAPINFOHEADER bi = {sizeof(BITMAPINFOHEADER)};
  bi.biWidth = frame_w_;
  bi.biHeight = -frame_h_;  // top-down DIB (no vertical flip)
  bi.biPlanes = 1;
  bi.biBitCount = 32;
  bi.biCompression = BI_RGB;
  HDC dc = GetDC(w);
  if (dc) {
    RECT rc;
    GetClientRect(w, &rc);
    // COLORONCOLOR drops pixels on downscale (no thin colored edge artifacts
    // like the default BLACKONWHITE stretch mode) and is the fastest mode.
    SetStretchBltMode(dc, COLORONCOLOR);
    if (rc.right == frame_w_ && rc.bottom == frame_h_) {
      // Source already matches the window 1:1: a direct DIB blit is faster than
      // a full-screen stretch and avoids any resampling.
      SetDIBitsToDevice(dc, 0, 0, frame_w_, frame_h_, 0, 0, 0, frame_h_,
                        frame_rgb_.data(), reinterpret_cast<BITMAPINFO*>(&bi),
                        DIB_RGB_COLORS);
    } else {
      // Mismatched size: stretch to fill the screen (cover).
      StretchDIBits(dc, 0, 0, rc.right, rc.bottom, 0, 0, frame_w_, frame_h_,
                    frame_rgb_.data(), reinterpret_cast<BITMAPINFO*>(&bi),
                    DIB_RGB_COLORS, SRCCOPY);
    }
    ReleaseDC(w, dc);
  }
}

void WallpaperEngine::clearPaintPending() {
  paint_pending_.store(false);
}

void WallpaperEngine::drawSample(void* pBufVoid, int w, int h, int strideYMedia) {
  IMFMediaBuffer* pBuf = static_cast<IMFMediaBuffer*>(pBufVoid);

  // Prefer the 2D buffer interface: it yields the decoder's AUTHORITATIVE row
  // pitch and contiguous length, which is the only reliable way to handle
  // height padding (e.g. 1080 -> 1088). Media Foundation decoders frequently
  // pad the encoded height to a multiple of 16; using the media type's declared
  // height to compute the UV-plane offset is exactly what produces the garbled
  // "outline correct, color scrambled" corruption.
  BYTE* pData = nullptr;
  LONG pitch = 0;
  DWORD curLen = 0;
  bool via2D = false;
  IMF2DBuffer* p2D = nullptr;
  if (SUCCEEDED(pBuf->QueryInterface(__uuidof(IMF2DBuffer), (void**)&p2D))) {
    BYTE* p2 = nullptr;
    LONG lp = 0;
    if (SUCCEEDED(p2D->Lock2D(&p2, &lp))) {
      pData = p2;
      pitch = lp;
      via2D = true;
      DWORD total = 0;
      if (SUCCEEDED(p2D->GetContiguousLength(&total))) curLen = total;
    }
  }
  if (!via2D) {
    DWORD maxLen = 0;
    if (FAILED(pBuf->Lock(&pData, &maxLen, &curLen)) || !pData) {
      if (p2D) p2D->Release();
      return;
    }
    pitch = strideYMedia;
  }

  int sY = (pitch > 0) ? (int)pitch : strideYMedia;  // real Y row pitch
  if (sY <= 0) sY = w * 4;
  bool planar = IsEqualGUID(out_subtype_, MFVideoFormat_NV12) ||
                IsEqualGUID(out_subtype_, MFVideoFormat_I420) ||
                IsEqualGUID(out_subtype_, MFVideoFormat_YV12);
  // Real padded height (integer division floors): used ONLY for plane offsets,
  // never for output row count. Flooring guarantees offsets stay inside the
  // buffer -> no over-read, no bad_alloc, no crash.
  int paddedH = h;
  if (curLen > 0 && sY > 0) {
    int maxH = planar ? (int)(curLen / (sY * 1.5)) : (int)(curLen / sY);
    if (maxH >= 1) paddedH = maxH;
  }

  {
    std::lock_guard<std::mutex> lk(frame_cs_);
    // Output height = display height, clamped to what the buffer actually holds
    // so we never read past the end of the samples.
    int outH = h;
    if (curLen > 0 && sY > 0) {
      int maxH = planar ? (int)(curLen / (sY * 1.5)) : (int)(curLen / sY);
      if (outH > maxH) outH = maxH;
    }
    if (outH < 1) outH = 1;
    size_t need = (size_t)w * outH * 4;
    if (frame_rgb_.size() != need) frame_rgb_.resize(need);
    frame_w_ = w;
    frame_h_ = outH;

    GUID sub = out_subtype_;
    if (IsEqualGUID(sub, MFVideoFormat_RGB32)) {
      const int row = w * 4;
      for (int y = 0; y < outH; ++y) {
        memcpy(frame_rgb_.data() + (size_t)y * row, pData + (size_t)y * sY,
               (size_t)row);
      }
    } else if (IsEqualGUID(sub, MFVideoFormat_RGB24)) {
      // 24-bit BGR (3 bytes/pixel) -> RGB32. Source row pitch sY may exceed w*3.
      for (int y = 0; y < outH; ++y) {
        const BYTE* row = pData + (size_t)y * sY;
        BYTE* rgbRow = frame_rgb_.data() + (size_t)y * w * 4;
        for (int x = 0; x < w; ++x) {
          rgbRow[x * 4] = row[x * 3];        // B
          rgbRow[x * 4 + 1] = row[x * 3 + 1];  // G
          rgbRow[x * 4 + 2] = row[x * 3 + 2];  // R
          rgbRow[x * 4 + 3] = 0;
        }
      }
    } else if (IsEqualGUID(sub, MFVideoFormat_YUY2) ||
               IsEqualGUID(sub, MFVideoFormat_UYVY)) {
      Yuy2ToRgb32(pData, w, outH, sY, frame_rgb_.data(),
                  IsEqualGUID(sub, MFVideoFormat_UYVY));
    } else if (IsEqualGUID(sub, MFVideoFormat_NV12)) {
      // Chroma plane starts after paddedH rows of Y (NOT display height).
      Nv12ToRgb32(pData, pData + (size_t)sY * paddedH, w, outH, sY,
                  frame_rgb_.data());
    } else if (IsEqualGUID(sub, MFVideoFormat_I420) ||
               IsEqualGUID(sub, MFVideoFormat_YV12)) {
      // U and V follow the padded Y plane, each with stride sY/2.
      int sUV = sY / 2;
      const BYTE* Y = pData;
      const BYTE* U = pData + (size_t)sY * paddedH;
      const BYTE* V = U + (size_t)sUV * (paddedH / 2);
      if (IsEqualGUID(sub, MFVideoFormat_YV12)) {
        const BYTE* t = U; U = V; V = t;  // YV12 stores V before U
      }
      I420ToRgb32(Y, U, V, w, outH, sY, sUV, sUV, frame_rgb_.data());
    } else {
      // Unknown subtype: best-effort treat as NV12 (semi-planar) but CLAMP the
      // chroma offset so we never read past the buffer -- this is what previously
      // crashed the app (garbage U/V offsets past the end of the sample). No
      // crash; the pin above normally prevents reaching here.
      size_t uvOff = (size_t)sY * paddedH;
      size_t chroma = (size_t)sY * (paddedH / 2);
      if (uvOff + chroma > curLen) {
        uvOff = (curLen > chroma) ? (curLen - chroma) : 0;
      }
      Nv12ToRgb32(pData, pData + uvOff, w, outH, sY, frame_rgb_.data());
    }
  }

  // Unlock the buffer now (do NOT hold frame_cs_ while the window repaints).
  if (via2D) p2D->Unlock2D();
  else pBuf->Unlock();
  if (p2D) p2D->Release();

  // Present via WM_PAINT, not a direct StretchDIBits to the DC. For a window
  // reparented into the cross-process WorkerW wallpaper layer, DWM does NOT
  // re-composite a direct DC draw -- the last presented frame (the initial
  // black brush) just stays, which is exactly the "black screen" symptom.
  // InvalidateRect triggers a real WM_PAINT, which our RenderWndProc handles by
  // calling blit(); that paint is composited and shown.
  //
  // Do NOT call UpdateWindow() here: it synchronously stretched the full screen
  // on EVERY decoded frame, blocking the decode/pump thread and tanking the
  // frame rate. Instead we just queue a WM_PAINT and let the thread's message
  // pump dispatch it; paint_pending_ coalesces bursts of decoded frames into a
  // single paint per pump pass, so decode rate no longer throttles playback.
  if (render_hwnd_ && !paint_pending_.exchange(true)) {
    InvalidateRect(render_hwnd_, nullptr, FALSE);
  }
}

void WallpaperEngine::renderThread() {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  HWND w = createRenderWindow(parent_);
  if (!w) {
    signalReady("createwindow_failed");
    CoUninitialize();
    return;
  }
  {
    std::lock_guard<std::mutex> lk(mtx_);
    render_hwnd_ = w;
  }
  SetWindowPos(w, HWND_BOTTOM, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ShowWindow(w, SW_SHOW);

  // Create the Source Reader on the mp4 file.
  IMFAttributes* attr = nullptr;
  MFCreateAttributes(&attr, 1);
  if (attr) attr->SetUINT32(MF_READWRITE_DISABLE_CONVERTERS, 0);
  IMFSourceReader* reader = nullptr;
  HRESULT hr = MFCreateSourceReaderFromURL(video_path_.c_str(), attr, &reader);
  if (attr) attr->Release();
  if (FAILED(hr) || !reader) {
    char buf[64];
    snprintf(buf, sizeof(buf), "reader_failed:0x%08X",
             static_cast<unsigned>(hr));
    {
      std::lock_guard<std::mutex> lk(mtx_);
      if (render_hwnd_) { DestroyWindow(render_hwnd_); render_hwnd_ = nullptr; }
    }
    signalReady(std::string(buf));
    CoUninitialize();
    return;
  }

  // Pin a render-friendly output type (RGB32 preferred, NV12 native) WITH the
  // frame size set -- a bare subtype-only type is rejected (MF_E_INVALIDMEDIATYPE
  // = 0xC00D36B4). This sidesteps the earlier "settype_failed" and, for RGB32,
  // removes any colorspace conversion on our side. If it fails we fall back to
  // the decoder's default output, which ReadCurrentVideoType then reports.
  PinOutputType(reader);
  GUID subtype = GUID_NULL;
  int fw = 0, fh = 0;
  int strideY = 0;
  ReadCurrentVideoType(reader, subtype, fw, fh, strideY);
  if (IsCompressedVideo(subtype)) {
    // No decoder MFT for this codec on the system (e.g. HEVC/H.265 without the
    // HEVC Video Extensions). The Source Reader passes through the raw bitstream,
    // which cannot be painted -> would show garbled (花屏). Report it clearly and
    // bail out instead of corrupting the screen.
    char buf[64];
    snprintf(buf, sizeof(buf), "no_decoder:%s", SubtypeName(subtype));
    {
      std::lock_guard<std::mutex> lk(mtx_);
      if (render_hwnd_) { DestroyWindow(render_hwnd_); render_hwnd_ = nullptr; }
    }
    reader->Release();
    signalReady(std::string(buf));
    CoUninitialize();
    return;
  }
  {
    std::lock_guard<std::mutex> lk(frame_cs_);
    out_subtype_ = subtype;
  }
  if (fw == 0) fw = GetSystemMetrics(SM_CXSCREEN);
  if (fh == 0) fh = GetSystemMetrics(SM_CYSCREEN);
  if (strideY <= 0) strideY = (fw + 15) & ~15;  // aligned fallback, like decoders

  // Report success as soon as the reader is ready and the window is injected.
  {
    char okbuf[64];
    snprintf(okbuf, sizeof(okbuf), "ok sp=%d fmt=%s %dx%d",
             setparent_ok_ ? 1 : 0, SubtypeName(subtype), fw, fh);
    signalReady(std::string(okbuf));
  }

  // Decode / paint loop.
  bool typed = false;  // true after the first authoritative type read
  LONGLONG ptsBase = -1;   // PTS (100ns) of the first paced frame
  ULONGLONG tickBase = 0;  // wall-clock tick at the first paced frame
  while (running_.load()) {
    DWORD streamIdx = 0, flags = 0;
    LONGLONG llTime = 0;
    IMFSample* pSample = nullptr;
    HRESULT r = reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
                                   &streamIdx, &flags, &llTime, &pSample);
    if (FAILED(r)) {
      // Transient decode error: small pause then retry; stop only if asked.
      Sleep(50);
      continue;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      // Loop: seek back to the start.
      PROPVARIANT var;
      PropVariantInit(&var);
      var.vt = VT_I8;
      var.hVal.QuadPart = 0;
      reader->SetCurrentPosition(GUID_NULL, var);
      PropVariantClear(&var);
      if (pSample) pSample->Release();
      ptsBase = -1;  // re-base the pacing clock on the next loop
      continue;
    }
    if (pSample) {
      if (!typed) {
        // Re-read the authoritative output type now that the decode pipeline is
        // active (more reliable than the pre-loop read on some systems).
        GUID rs = GUID_NULL;
        int rf = 0, rh = 0, rstr = 0;
        ReadCurrentVideoType(reader, rs, rf, rh, rstr);
        if (rf != 0 && rh != 0) { fw = rf; fh = rh; strideY = rstr; }
        {
          std::lock_guard<std::mutex> lk(frame_cs_);
          out_subtype_ = rs;
        }
        typed = true;
      }

      // Pace to this sample's presentation timestamp so the wallpaper plays at
      // its native frame rate (e.g. 60fps) instead of an artificial ~30fps cap.
      // We sleep only the remaining slice of this frame's slot, which also keeps
      // CPU bounded at the video's rate rather than decode-as-fast-as-possible.
      if (llTime > 0) {
        if (ptsBase < 0) {
          ptsBase = llTime;
          tickBase = GetTickCount64();
        } else {
          LONGLONG targetMs =
              static_cast<LONGLONG>(tickBase) + (llTime - ptsBase) / 10000;
          LONGLONG nowMs = static_cast<LONGLONG>(GetTickCount64());
          LONGLONG delta = targetMs - nowMs;
          if (delta > 250) delta = 250;  // clamp after a long stall / seek / loop
          if (delta > 0) Sleep(static_cast<DWORD>(delta));
        }
      }
      IMFMediaBuffer* pBuf = nullptr;
      if (SUCCEEDED(pSample->GetBufferByIndex(0, &pBuf)) && pBuf) {
        drawSample(pBuf, fw, fh, strideY);
        pBuf->Release();
      }
      pSample->Release();
    }
    // Pump window messages (WM_PAINT / repaint) without blocking.
    MSG msg;
    while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) { running_.store(false); break; }
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }
    if (!running_.load()) break;
    // (Per-frame pacing above sleeps to the sample PTS; no fixed cap here.)
  }

  reader->Release();
  {
    std::lock_guard<std::mutex> lk(mtx_);
    if (render_hwnd_) {
      DestroyWindow(render_hwnd_);
      render_hwnd_ = nullptr;
    }
  }
  CoUninitialize();
}

void WallpaperEngine::restoreWallpaper() {
  // The 0x052C WorkerW injection can leave the desktop blank after we remove our
  // window. Re-apply the user's current wallpaper so Windows repaints it.
  wchar_t path[MAX_PATH] = {0};
  DWORD sz = sizeof(path);
  HKEY hk = nullptr;
  if (RegOpenKeyEx(HKEY_CURRENT_USER, L"Control Panel\\Desktop", 0, KEY_READ,
                   &hk) == ERROR_SUCCESS) {
    RegQueryValueEx(hk, L"Wallpaper", 0, nullptr, (BYTE*)path, &sz);
    RegCloseKey(hk);
  }
  if (path[0]) {
    SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, (void*)path,
                         SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
  }
  InvalidateRect(HWND_DESKTOP, nullptr, TRUE);
  UpdateWindow(HWND_DESKTOP);
}

std::string WallpaperEngine::start(const std::wstring& videoPath) {
  if (!isSupported()) return "unsupported_platform";
  stop();  // tear down any previous run first

  HWND parent = findWorkerW();
  if (!parent) return "no_workerw_parent";

  video_path_ = videoPath;
  parent_ = parent;

  std::promise<std::string> prom;
  auto fut = prom.get_future();
  {
    std::lock_guard<std::mutex> lk(ready_mux_);
    ready_prom_ = &prom;
  }

  running_.store(true);
  render_thread_ = std::thread([this]() { renderThread(); });

  auto status = fut.wait_for(std::chrono::seconds(5));
  {
    std::lock_guard<std::mutex> lk(ready_mux_);
    ready_prom_ = nullptr;
  }
  if (status == std::future_status::ready) {
    return fut.get();
  }
  return "";  // timed out but likely still loading; video should appear soon
}

void WallpaperEngine::stop() {
  running_.store(false);
  HWND w = nullptr;
  {
    std::lock_guard<std::mutex> lk(mtx_);
    w = render_hwnd_;
  }
  if (w) PostMessage(w, WM_QUIT, 0, 0);
  if (render_thread_.joinable()) render_thread_.join();
  restoreWallpaper();
}
