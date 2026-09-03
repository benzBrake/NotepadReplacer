# NotepadReplacer

NotepadReplacer 是一个 Windows 记事本替代工具，可将系统对 `notepad.exe` 的调用转发到用户指定的文本编辑器，并在 Windows 11 文件资源管理器中提供“使用记事本打开”右键菜单。

项目通过安装包完成目标程序选择、Microsoft Store 版记事本移除、系统配置写入、右键菜单部署和卸载清理。`NotepadReplacerLauncher` 是其中负责转发进程调用的轻量组件，并非项目本身的名称。

## 功能

- 将系统对 `notepad.exe` 的调用转发到指定的 `.exe` 程序。
- 根据系统架构部署 Launcher；在 64 位系统上同时配置 32 位和 64 位 IFEO 注册表视图。
- 按 Windows 命令行规则转义并转发有效参数，正确处理空格、引号和反斜杠。
- 在 64 位 Windows 11 的文件资源管理器顶层右键菜单中提供“使用记事本打开”。
- 支持从右键菜单一次打开多个选中的文件。
- 提供中英文安装界面，以及安装失败回滚和卸载清理。

## 安装与使用

1. 以管理员身份运行 `NotepadReplacerSetup.exe`。
2. 选择要替代 Windows 记事本的可执行文件，例如其他文本编辑器的 `.exe` 文件。
3. 确认移除 Microsoft Store 版 Notepad，等待安装完成。
4. 此后，通过 `notepad.exe` 打开的文件会转交给所选程序；在支持的 Windows 11 系统中，也可以使用文件右键菜单中的“使用记事本打开”。

安装目录固定为系统盘下的 `Program Files\NotepadReplacer`。目标程序的路径记录在：

```text
HKEY_LOCAL_MACHINE\SOFTWARE\NotepadReplacer\TargetPath
```

### 使用前须知

- 安装程序需要管理员权限。
- 安装会移除当前用户已安装的 Microsoft Store 版 Notepad，并移除系统中的对应预配包。
- 卸载 NotepadReplacer **不会自动恢复 Microsoft Store 版 Notepad**，需要时请从 Microsoft Store 手动重新安装。
- 所选替代程序必须保持在原路径；文件被移动或删除后，转发与右键菜单将无法正常工作。
- 如果系统中已有不属于本项目的 `notepad.exe` IFEO Debugger 配置，安装程序会停止，以免覆盖现有配置。
- 完整的 x64 安装流程要求 64 位 Windows 11（Build 22000 或更高版本）。右键菜单包无法注册时，安装会回滚。

## 工作原理

NotepadReplacer 由安装与配置流程、进程转发组件和 Windows 11 右键菜单组件共同组成：

| 部分 | 职责 |
| --- | --- |
| `NotepadReplacerSetup.exe` | 选择目标程序、移除 Store 版 Notepad、部署文件、写入 IFEO 和目标路径，并处理回滚与卸载 |
| `NotepadReplacerLauncher` | 接收 IFEO Debugger 参数，移除其中由 Windows 附加的 `notepad.exe` 路径，再将其余参数转发给目标程序 |
| `NotepadReplacerContextMenu.dll` | 实现 Windows 11 文件资源管理器命令，将选中的文件传给已配置的目标程序 |
| `NotepadReplacer.msix` | 通过 `windows.fileExplorerContextMenus` 扩展注册右键菜单及 COM 组件 |

安装器将对应架构的 Launcher 写入以下 IFEO 配置：

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\notepad.exe
```

调用链如下：

```text
应用程序或命令行调用 notepad.exe
  -> Windows 根据 IFEO 启动 NotepadReplacerLauncher
  -> Launcher 清理 IFEO 附加参数
  -> Launcher 创建所选目标程序的进程并立即退出
```

右键菜单不经过 `notepad.exe`，而是读取安装器保存的目标路径，直接启动目标程序并传入所有选中文件。

## 从源码构建

### 环境要求

- Visual Studio 2022，包含“使用 C++ 的桌面开发”工作负载
- CMake 3.21 或更高版本
- Windows 10/11 SDK
- Inno Setup 6（仅构建安装包时需要）

### 构建程序组件

运行构建脚本，生成安装器所需的 x64 Launcher、x64 右键菜单 DLL 和 x86 Launcher：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

脚本默认构建 Release 版本并使用静态 MSVC 运行库。可通过 `-Configuration Debug` 构建其他配置，或通过 `-DynamicRuntime` 改用动态运行库（目标系统需要安装对应版本的 Visual C++ Runtime）。

所有构建产物统一写入 `dist`：x64 和 x86 的 CMake 构建目录分别为 `dist\x64` 与 `dist\x86`，右键菜单包位于 `dist\context-menu-package`。

如只需构建 Launcher，可关闭 Windows 11 右键菜单组件：

```powershell
cmake -S . -B dist/x64 -G "Visual Studio 17 2022" -A x64 -DNOTEPADREPLACER_BUILD_CONTEXT_MENU=OFF
```

运行测试：

```powershell
ctest --test-dir dist/x64 -C Release --output-on-failure
```

### 构建安装包

完成 x64 和 x86 Release 构建后执行：

```powershell
powershell -ExecutionPolicy Bypass -File installer/build-installer.ps1
```

脚本会完成以下工作：

1. 检查 x86、x64 Launcher 和 x64 右键菜单 DLL。
2. 使用 Windows SDK 的 `MakeAppx.exe` 生成 MSIX 包。
3. 使用 `SignTool.exe` 签名 MSIX，并导出安装时所需的证书。
4. 调用 Inno Setup 的 `ISCC.exe` 生成最终安装程序。

输出文件位于：

```text
dist\NotepadReplacerSetup.exe
```

首次构建安装包前，在本地生成固定的自签名证书：

```powershell
powershell -ExecutionPolicy Bypass -File installer/New-SigningCertificate.ps1
```

生成的 PFX、密码和 Base64 文件位于 `.certificates`，该目录已被 Git 忽略。`build-installer.ps1` 优先使用本地的 `NotepadReplacer.pfx` 和 `NotepadReplacer.password`；本地文件不存在时，改用环境变量 `WINDOWS_CERTIFICATE`（PFX 的 Base64）与 `WINDOWS_CERTIFICATE_PASSWORD`。

GitHub Actions 中，将 `.certificates/NotepadReplacer.pfx.base64` 的内容保存为仓库 Secret `WINDOWS_CERTIFICATE`，将 `.certificates/NotepadReplacer.password` 的内容保存为 `WINDOWS_CERTIFICATE_PASSWORD`。这样本地与远程构建会使用同一张证书。

安装右键菜单时，安装器会将 MSIX 签名证书加入本机 `TrustedPeople` 证书存储区；卸载时会移除该证书。

## 故障排查

如果 Windows 11 右键菜单注册失败，安装会回滚。PowerShell 和 AppX 的详细错误记录在：

```text
%ProgramData%\NotepadReplacer\context-menu.log
```

Launcher 是 Windows 子系统程序，不显示控制台窗口；它在创建目标进程后立即退出，不等待目标程序结束。

## 许可证

本项目采用 [GNU General Public License v3.0 or later](LICENSE) 授权，并适用
[GPLv3 第 7 节附加条款](ADDITIONAL-TERMS.md)。你可以使用、研究、修改和分发
本软件；向他人分发原版或修改版时，必须按 GPL 提供完整对应源码并保留适用声明，
不得将受 GPL 约束的二开版本闭源分发。

附加条款要求保留原始材料由 AI 辅助、通过 vibe coding 开发的来源声明，并禁止
把原始材料歪曲为完全由传统手工编程、未借助 AI 或“非 vibe coding”完成。
修改者可以如实说明自己独立创作部分所采用的开发方式。

`replacer.ico` 与 `installer/logo.png` 是第三方素材，不因上述声明而被重新授权；
再分发者需要遵守素材原权利人的许可，或将其替换为有权分发的素材。

## 图片来源

`replacer.ico` 和 `installer/logo.png` 来源于 [Iconbuddy](https://iconbuddy.com/)。
