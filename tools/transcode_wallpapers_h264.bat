@echo off
REM ============================================================================
REM  Olivia 动态桌面壁纸：HEVC -> H.264 批量转码脚本
REM
REM  背景：素材 Wallpaper_Presence\*.mp4 是 H.265/HEVC 编码；部分 Windows 机器
REM        默认没有 HEVC 解码器（Microsoft 商店的「HEVC 视频扩展」未安装），
REM        原生客户端动态桌面会花屏 / 无法播放。Windows 自带 H.264 解码器，
REM        转码成 H.264 后任意机器都能直接播放，无外部依赖。
REM
REM  用法：
REM    1) 安装 ffmpeg 并确保在 PATH 中（https://ffmpeg.org 或 scoop install ffmpeg）
REM    2) 若素材目录不同，把下面 SRC 改成你机器上的 Wallpaper_Presence 目录
REM    3) 双击本脚本（或右键“以管理员身份运行”）
REM    4) 原 HEVC 文件自动备份到 Wallpaper_Presence_HEVC_backup\
REM    5) 重新启动 Olivia 客户端，开启动态桌面即可看到视频
REM ============================================================================
setlocal EnableDelayedExpansion
set "SRC=E:\work\BSide Olivia Lin Test\0.0.9.615\assets\Wallpaper_Presence"
set "BAK=%SRC%_HEVC_backup"

where ffmpeg >nul 2>nul || (
  echo [错误] 未找到 ffmpeg，请先安装并加入 PATH（https://ffmpeg.org）。
  pause
  exit /b 1
)

if not exist "%SRC%" (
  echo [错误] 素材目录不存在：%SRC%
  echo 请在脚本顶部把 SRC 改成你机器上的 Wallpaper_Presence 目录。
  pause
  exit /b 1
)

if not exist "%BAK%" mkdir "%BAK%"

echo 开始转码 HEVC -^> H.264（去除音轨，yuv420p，保持分辨率与帧率）...
for %%f in ("%SRC%\*.mp4") do (
  echo.
  echo == %%~nxf ==
  if not exist "%BAK%\%%~nxf" copy "%%f" "%BAK%\%%~nxf" >nul && echo    备份原文件 -^> %BAK%\%%~nxf
  ffmpeg -y -i "%%f" -an -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p "%%~dpnf.tmp.mp4"
  if exist "%%~dpnf.tmp.mp4" (
    move /y "%%~dpnf.tmp.mp4" "%%f" >nul
    echo    完成
  ) else (
    echo    [失败] 原文件保留，请手动检查
  )
)
echo.
echo 全部完成。原 HEVC 文件位于 %BAK%
echo 重新启动 Olivia 客户端即可看到动态桌面。
pause
