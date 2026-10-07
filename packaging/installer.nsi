; ============================================================
;  Olivia 安可 4.0  ——  NSIS 向导式安装脚本
;  使用方法（在 installer 目录执行）：
;      makensis installer.nsi
;  前提：已先运行 `flutter build windows --release`，
;        产物位于  ..\build\windows\x64\runner\Release\
;  本脚本将该 Release 目录整体打包为熟悉的“下一步/下一步”安装向导。
;  采用「当前用户」安装（写入 %LOCALAPPDATA%），无需管理员权限。
; ============================================================

!include "MUI2.nsh"

; ---------- 版本号（与 pubspec.yaml 的 msix_version 保持一致） ----------
!define VERSION "4.0.3.0"

; ---------- 基本信息 ----------
Name "Olivia 安可 4.0"
OutFile "OliviaAnk4-Setup-${VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\OliviaAnk4"
InstallDirRegKey HKCU "Software\OliviaAnk4" "InstallDir"

; ---------- 图标（安装包 / 卸载程序 / 快捷方式共用）----------
!define MUI_ICON "..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\windows\runner\resources\app_icon.ico"

; ---------- 界面 ----------
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"

; ---------- 安装区段 ----------
Section "Main" SecMain
  SetOutPath "$INSTDIR"
  ; 将 Flutter Release 目录整体复制进来（含 exe / dll / data 资源）
  File /r "..\build\windows\x64\runner\Release\*.*"

  ; 开始菜单快捷方式
  CreateDirectory "$SMPROGRAMS\Olivia 安可 4.0"
  CreateShortcut "$SMPROGRAMS\Olivia 安可 4.0\Olivia 安可 4.0.lnk" "$INSTDIR\olivia_ank4.exe"

  ; 桌面快捷方式
  CreateShortcut "$DESKTOP\Olivia 安可 4.0.lnk" "$INSTDIR\olivia_ank4.exe"

  ; 卸载信息（HKCU，无需管理员）
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "DisplayName" "Olivia 安可 4.0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "DisplayIcon" "$INSTDIR\olivia_ank4.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "Publisher" "Olivia"
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4" "NoRepair" 1

  ; 记录安装路径
  WriteRegStr HKCU "Software\OliviaAnk4" "InstallDir" "$INSTDIR"

  ; 生成卸载程序
  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

; ---------- 卸载区段 ----------
Section "Uninstall"
  RMDir /r "$INSTDIR"
  Delete "$SMPROGRAMS\Olivia 安可 4.0\Olivia 安可 4.0.lnk"
  RMDir "$SMPROGRAMS\Olivia 安可 4.0"
  Delete "$DESKTOP\Olivia 安可 4.0.lnk"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\OliviaAnk4"
  DeleteRegKey HKCU "Software\OliviaAnk4"
SectionEnd
