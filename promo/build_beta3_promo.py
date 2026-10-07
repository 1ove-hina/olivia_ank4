# -*- coding: utf-8 -*-
"""Olivia 安可 4.0 Beta3 · 宣传片合成（色轮转场）

参考风格：B站「Écoute chérie MEME / 色轮转场背景模板」——段与段之间用
旋转张开的扇形色轮扫过画面完成切换。

素材：promo/ 下三段 5.04s / 24fps 真实界面动态素材（1916x1080 等，略有出入）
输出：promo/OliviaAnk4_Beta3_Promo.mp4（1920x1080 / 24fps / H.264 / 无音轨）

流程：
  1) ffmpeg 把三段素材统一 scale+crop 到 1920x1080，rawvideo 管道逐帧读出
  2) numpy 逐帧合成：主时间轴拼接 + 两处色轮转场 + 字幕/片头/片尾
  3) ffmpeg 从管道接收 rawvideo 编码为 MP4
"""
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import imageio_ffmpeg

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
FF = imageio_ffmpeg.get_ffmpeg_exe()

# ------------------------------------------------------------------ 规格常量
W, H, FPS = 1920, 1080, 24
NBYTES = W * H * 3

SEG = 121          # 每段素材帧数（5.04s）
XF = 24            # 转场帧数（1.0s）
LEAD = SEG - XF    # 首段独占 97
MID = SEG - 2 * XF # 中段独占 73
TAIL = SEG - XF    # 末段独占 97
FREEZE = 21        # 片尾定格
TOTAL = LEAD + XF + MID + XF + TAIL + FREEZE  # 336 帧 = 14.0s

V1 = os.path.join(HERE, "Cinematic_slow_push_in_zoom_on_2026-08-31T15-53-54.mp4")
V2 = os.path.join(HERE, "Slow_gentle_pan_across_a_lette_2026-08-31T15-54-00.mp4")
V3 = os.path.join(HERE, "Smooth_slow_zoom_in_on_an_app__2026-08-31T15-54-04.mp4")
OUT = os.path.join(HERE, "OliviaAnk4_Beta3_Promo.mp4")
SHOTS_DIR = os.path.join(HERE, "_preview_frames")

# ------------------------------------------------------------------ 配色 / 字体
GOLD = (232, 177, 76)
WHITE = (255, 255, 255)
INK = (10, 10, 14)

FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"
FONT_REG = "C:/Windows/Fonts/msyh.ttc"

# 色轮 12 色（高饱和，贴近参考视频的 MEME 风）
WHEEL_COLORS = np.array(
    [
        (255, 82, 82), (255, 138, 0), (255, 214, 0), (170, 220, 0),
        (60, 200, 90), (0, 200, 180), (0, 160, 255), (60, 110, 255),
        (140, 80, 255), (220, 70, 220), (255, 60, 160), (255, 90, 90),
    ],
    dtype=np.float32,
)

# ------------------------------------------------------------------ 极坐标网格
_yy, _xx = np.mgrid[0:H, 0:W]
_cx, _cy = (W - 1) / 2.0, (H - 1) / 2.0
_dx = (_xx - _cx).astype(np.float32)
_dy = (_yy - _cy).astype(np.float32)
THETA = (np.arctan2(_dy, _dx) / (2.0 * np.pi)) % 1.0      # 0..1 归一化角度
RADIUS = np.sqrt(_dx * _dx + _dy * _dy)
R_MAX = float(np.sqrt(_cx * _cx + _cy * _cy))              # 到画面角点
del _yy, _xx, _dx, _dy

EDGE = 0.07       # 波前柔化带宽度（占 R_MAX 比例）
WAVES = 3         # 花瓣数（波前随角度起伏，形成旋转的花瓣边界）


def sweep_mask(p: float) -> np.ndarray:
    """色轮转场遮罩：旋转的花瓣形波前自中心向外扩散。

    相比「从中心张开的扇形」，花瓣波前没有径向尖角，边界随色轮一起旋转，
    收尾更干净。返回 0..1 权重（1 = 显示新场景 B，0 = 保留旧场景 A）。
    """
    mod = 1.0 + 0.35 * np.sin(2.0 * np.pi * (THETA * WAVES - p * 1.5))
    r_front = (p * 1.75) * R_MAX * mod
    return np.clip((r_front - RADIUS) / (EDGE * R_MAX), 0.0, 1.0).astype(np.float32)


def wheel_overlay(p: float):
    """可见的 12 色扇形色轮：自中心放大并旋转，alpha 呈 sin 曲线。

    返回 (rgb, alpha)，alpha 为 0..1 的 (H, W) 数组。
    """
    r_out = R_MAX * (0.25 + 2.00 * p)
    r_in = r_out * 0.40
    ring = ((RADIUS >= r_in) & (RADIUS <= r_out)).astype(np.float32)

    rot = p * 1.5
    sector = (((THETA - rot) % 1.0) * len(WHEEL_COLORS)).astype(np.int32)
    sector %= len(WHEEL_COLORS)
    rgb = WHEEL_COLORS[sector]                       # (H, W, 3)

    gain = float(np.sin(np.pi * p) ** 0.5) * 0.95
    alpha = ring * gain
    return rgb, alpha


# ------------------------------------------------------------------ 文字层
_font_cache: dict = {}


def _font(path: str, size: int):
    key = (path, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


def _to_arrays(img: Image.Image):
    """RGBA PIL 图 → (rgb float32, alpha float32 0..1)"""
    arr = np.asarray(img, dtype=np.uint8)
    rgb = arr[:, :, :3].astype(np.float32)
    alpha = arr[:, :, 3].astype(np.float32) / 255.0
    return rgb, alpha


def make_caption(text: str):
    """卖点字幕：深色半透明圆角条 + 白色粗体字（浅色信纸画面上也清晰）"""
    f = _font(FONT_BOLD, 46)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    tw = probe.textlength(text, font=f)
    padx, pady = 46, 24
    w = int(tw) + padx * 2
    h = f.size + pady * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=18, fill=(10, 10, 14, 172))
    d.text((w / 2, pady + f.size / 2), text, font=f, fill=(255, 255, 255, 255),
           anchor="mm")
    return _to_arrays(img)


def make_title(main: str, sub: str):
    """片头标题：白色粗体主标 + 金色副标，带投影"""
    f_main = _font(FONT_BOLD, 92)
    f_sub = _font(FONT_REG, 34)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    w_main = probe.textlength(main, font=f_main)
    w_sub = probe.textlength(sub, font=f_sub)
    pad = 40
    w = int(max(w_main, w_sub)) + pad * 2
    h = f_main.size + 22 + f_sub.size + pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy1 = pad + f_main.size / 2
    cy2 = pad + f_main.size + 22 + f_sub.size / 2
    # 投影
    d.text((w / 2 + 3, cy1 + 3), main, font=f_main, fill=(0, 0, 0, 150), anchor="mm")
    d.text((w / 2 + 2, cy2 + 2), sub, font=f_sub, fill=(0, 0, 0, 130), anchor="mm")
    d.text((w / 2, cy1), main, font=f_main, fill=(255, 255, 255, 255), anchor="mm")
    d.text((w / 2, cy2), sub, font=f_sub, fill=GOLD + (255,), anchor="mm")
    return _to_arrays(img)


def make_endcard(main: str, sub: str, note: str):
    """片尾卡：白主标 + 金副标 + 灰白提示"""
    f_main = _font(FONT_BOLD, 76)
    f_sub = _font(FONT_REG, 34)
    f_note = _font(FONT_REG, 26)
    probe = ImageDraw.Draw(Image.new("RGBA", (8, 8)))
    widths = [
        probe.textlength(main, font=f_main),
        probe.textlength(sub, font=f_sub),
        probe.textlength(note, font=f_note),
    ]
    pad = 40
    w = int(max(widths)) + pad * 2
    h = f_main.size + 20 + f_sub.size + 26 + f_note.size + pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cy1 = pad + f_main.size / 2
    cy2 = pad + f_main.size + 20 + f_sub.size / 2
    cy3 = pad + f_main.size + 20 + f_sub.size + 26 + f_note.size / 2
    d.text((w / 2, cy1), main, font=f_main, fill=(255, 255, 255, 255), anchor="mm")
    d.text((w / 2, cy2), sub, font=f_sub, fill=GOLD + (255,), anchor="mm")
    d.text((w / 2, cy3), note, font=f_note, fill=(200, 200, 208, 255), anchor="mm")
    return _to_arrays(img)


def blend_at(frame, rgb, alpha, x, y, gain=1.0):
    """把 (rgb, alpha) 叠加到 float32 帧的 (x, y) 处（原地修改）"""
    h, w = rgb.shape[:2]
    x0 = max(0, int(x))
    y0 = max(0, int(y))
    x1 = min(W, x0 + w)
    y1 = min(H, y0 + h)
    if x0 >= x1 or y0 >= y1:
        return
    sub_rgb = rgb[: y1 - y0, : x1 - x0]
    sub_a = alpha[: y1 - y0, : x1 - x0, None] * gain
    region = frame[y0:y1, x0:x1]
    region *= (1.0 - sub_a)
    region += sub_rgb * sub_a


# ------------------------------------------------------------------ 字幕排期
CAP1 = make_caption("数据加密 · 本地信件 AES 加密，隐私不落地")
CAP2 = make_caption("本地信件导入 · 原版历史信件一键搬")
CAP3 = make_caption("API 切换 · 自由配置 AI 服务与模型")
TITLE = make_title("Olivia 安可 4.0 Beta3", "林离的来信 · Write letters with AI")
ENDCARD = make_endcard("Olivia 安可 4.0 Beta3", "林离的来信",
                       "Windows 桌面端 · 交流群 863669648")


def _place(layer, cy_ratio):
    rgb, alpha = layer
    x = (W - rgb.shape[1]) / 2
    y = H * cy_ratio - rgb.shape[0] / 2
    return rgb, alpha, x, y


CAP1_P = _place(CAP1, 0.845)
CAP2_P = _place(CAP2, 0.845)
CAP3_P = _place(CAP3, 0.845)
TITLE_P = _place(TITLE, 0.50)
ENDCARD_P = _place(ENDCARD, 0.50)


def fade(i, a, b, steps=10):
    """帧 i 处，[a- steps, a] 淡入、[b, b+steps] 淡出的透明度系数"""
    if i < a - steps or i > b + steps:
        return 0.0
    if i < a:
        return (i - (a - steps)) / steps
    if i > b:
        return 1.0 - (i - b) / steps
    return 1.0


def apply_overlays(frame, i):
    """按时间轴叠加片头标题、三条卖点、片尾卡"""
    # 片头标题（0.25s 淡入，2.0s 后淡出）
    g = fade(i, 6, 48, 8)
    if g > 0:
        rgb, alpha, x, y = TITLE_P
        blend_at(frame, rgb, alpha, x, y, g)

    # 三条卖点
    for (layer, (a, b)) in ((CAP1_P, (55, 96)), (CAP2_P, (125, 192)), (CAP3_P, (222, 300))):
        g = fade(i, a, b, 8)
        if g > 0:
            rgb, alpha, x, y = layer
            blend_at(frame, rgb, alpha, x, y, g)

    # 片尾：黑幕压暗 + 卡片
    if i >= 315:
        k = min(1.0, (i - 315) / 12.0)
        frame *= (1.0 - 0.97 * k)
        g = fade(i, 320, 400, 8)
        if g > 0:
            rgb, alpha, x, y = ENDCARD_P
            blend_at(frame, rgb, alpha, x, y, g)
    return frame


# ------------------------------------------------------------------ 帧读取
class FrameStream:
    """把一段素材解码为 1920x1080 / 24fps 的 rgb24 帧流"""

    def __init__(self, path: str):
        cmd = [
            FF, "-hide_banner", "-loglevel", "error",
            "-i", path,
            "-vf", ("scale=1920:1080:force_original_aspect_ratio=increase,"
                    "crop=1920:1080,fps=24"),
            "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
        ]
        self.p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL)
        self.last = None
        self.count = 0

    def next(self) -> np.ndarray:
        buf = self.p.stdout.read(NBYTES)
        if len(buf) < NBYTES:
            # 素材不足时重复最后一帧，保证时间轴长度稳定
            if self.last is None:
                self.last = np.zeros((H, W, 3), np.uint8)
            return self.last
        self.last = np.frombuffer(buf, np.uint8).reshape(H, W, 3)
        self.count += 1
        return self.last

    def close(self):
        try:
            self.p.stdout.close()
        except Exception:
            pass
        self.p.wait()


def compose(a, b, p):
    """色轮转场：A → B"""
    fa = a.astype(np.float32)
    fb = b.astype(np.float32)
    m = sweep_mask(p)[:, :, None]
    out = fa * (1.0 - m) + fb * m
    ov_rgb, ov_a = wheel_overlay(p)
    a3 = ov_a[:, :, None]
    out *= (1.0 - a3)
    out += ov_rgb * a3
    return out


# ------------------------------------------------------------------ 主流程
def main():
    os.makedirs(SHOTS_DIR, exist_ok=True)
    shot_at = {6: "01_title", 70: "02_caption1",
               100: "03a_xfade1_early", 108: "03b_xfade1_mid", 117: "03c_xfade1_late",
               150: "04_caption2", 206: "05_xfade2", 260: "06_caption3",
               332: "07_endcard"}

    enc = subprocess.Popen(
        [FF, "-y", "-hide_banner", "-loglevel", "error",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS),
         "-i", "-",
         "-c:v", "libx264", "-preset", "medium", "-crf", "18",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", OUT],
        stdin=subprocess.PIPE, stderr=subprocess.PIPE,
    )

    s1, s2, s3 = FrameStream(V1), FrameStream(V2), FrameStream(V3)
    last3 = None

    try:
        for i in range(TOTAL):
            if i < LEAD:
                f = s1.next().astype(np.float32)
            elif i < LEAD + XF:
                p = (i - LEAD + 1) / XF
                f = compose(s1.next(), s2.next(), p)
            elif i < LEAD + XF + MID:
                f = s2.next().astype(np.float32)
            elif i < LEAD + XF + MID + XF:
                p = (i - (LEAD + XF + MID) + 1) / XF
                f = compose(s2.next(), s3.next(), p)
            elif i < TOTAL - FREEZE:
                f = s3.next().astype(np.float32)
            else:
                if last3 is None:
                    last3 = s3.next().astype(np.float32)
                f = last3.copy()
            if i == TOTAL - FREEZE - 1:
                last3 = f.copy()

            f = apply_overlays(f, i)

            if i in shot_at:
                Image.fromarray(np.clip(f, 0, 255).astype(np.uint8)).save(
                    os.path.join(SHOTS_DIR, f"{shot_at[i]}.png"))

            enc.stdin.write(np.clip(f, 0, 255).astype(np.uint8).tobytes())
            if i % 60 == 0:
                print(f"  frame {i}/{TOTAL}", flush=True)
    finally:
        s1.close()
        s2.close()
        s3.close()
        enc.stdin.close()
        err = enc.stderr.read().decode("utf-8", "replace")
        enc.wait()

    if err.strip():
        print("ffmpeg stderr:", err.strip()[:800], flush=True)

    size = os.path.getsize(OUT) / 1024 / 1024
    print(f"OK -> {OUT} ({size:.1f} MB, {TOTAL} frames / {TOTAL / FPS:.2f}s)")
    print(f"preview frames -> {SHOTS_DIR}")


if __name__ == "__main__":
    main()
