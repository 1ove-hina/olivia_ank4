# Olivia 安可 4.0 Beta1 宣传片 · 素材与成片指南

本目录包含用真实软件截图生成的**三段动态展示视频**（各 5 秒，1080P）：

| 文件 | 内容 | 镜头 |
|------|------|------|
| `Cinematic_slow_push_in_zoom_on_2026-08-31T15-53-54.mp4` | 信箱主界面 | 缓慢推近 + 金色柔光 |
| `Slow_gentle_pan_across_a_lette_2026-08-31T15-54-00.mp4` | AI 写信界面（信纸背景） | 横向平移 + 光扫 |
| `Smooth_slow_zoom_in_on_an_app__2026-08-31T15-54-04.mp4` | 设置页（版本号/导入） | 缓慢放大 + 背景虚化 |

`promo_preview.html` 是浏览器预览页：打开即按顺序交叉淡入淡出循环播放三段，模拟完整宣传片观感。

> 注：AI 视频工具无法准确生成中文卖点字幕，故视频本身只做画面与镜头，卖点文字建议放在发布配文或通过剪辑软件叠加。

---

## 一、把三段拼成一段完整 MP4

### 方式 A：ffmpeg（实体机，推荐）
```bat
cd promo
(echo file 'Cinematic_slow_push_in_zoom_on_2026-08-31T15-53-54.mp4'
 echo file 'Slow_gentle_pan_across_a_lette_2026-08-31T15-54-00.mp4'
 echo file 'Smooth_slow_zoom_in_on_an_app__2026-08-31T15-54-04.mp4') > list.txt

rem 若三段编码一致，直接复制流（最快、无损）：
ffmpeg -f concat -safe 0 -i list.txt -c copy OliviaAnk4_Beta1_Promo.mp4

rem 若报编码不一致，改为重编码：
ffmpeg -f concat -safe 0 -i list.txt -c:v libx264 -c:a aac OliviaAnk4_Beta1_Promo.mp4
```

### 方式 B：剪映 / 必剪（无命令行，最易加字幕）
1. 导入 3 段视频，按序拖入轨道。
2. 在每段之间加「交叉淡化」转场（0.5–0.8 秒）。
3. 叠加中文卖点字幕（见下文）。
4. 导出 1080P / 30fps。

---

## 二、叠加中文卖点字幕（视频工具做不了的，这里补）

按时间轴在对应画面加文字（可用剪映「文字」或 ffmpeg 烧录 .ass）：

- 0–5s（信箱界面）：`数据加密 · 本地信件 AES 加密，隐私不落地`
- 5–10s（写信界面）：`本地信件导入 · 原版历史信件一键搬过来`
- 10–15s（设置页）：`API 切换 · 自由配置 AI 服务与模型`

片头/片尾可加：`Olivia 安可 4.0` + `Write letters with AI`。

---

## 三、加背景音乐
选一段无版权 BGM（如 YouTube 音频库 / 爱给网免费曲），用剪映混音或 ffmpeg：
```bat
ffmpeg -i OliviaAnk4_Beta1_Promo.mp4 -i bgm.mp3 -c:v copy -c:a aac -shortest OliviaAnk4_Beta1_Promo_WithBGM.mp4
```

---

## 四、发布配文（直接复制）

> 【Olivia 安可 4.0 宣传片】
> 三段真实界面带你快速了解：
> 🔐 数据加密 — 本地信件 AES 加密，隐私不落地
> 📂 本地信件导入 — 原版历史信件一键搬
> 🌐 API 切换 — 自由配置 AI 服务与模型
> 🎬 观看：<视频链接>
> 📥 下载：https://1816693452.share.123pan.cn/123pan/ay86Vv-igAH3
> 💬 交流群：1058430826

适用场景：QQ 群公告、官网嵌入、B站/抖音短视频简介。
