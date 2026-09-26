# Gemini Windows Reopen Fix

修复 Google 官方 Gemini Windows 客户端的特定退出问题：关闭窗口后后台进程残留，再点图标或托盘无法打开，必须先结束进程。

**非 Google 官方项目。** 这是针对已确认代码的本地修复工具。单台 Windows x64 电脑上验证了 1.11.4 / 1.12.3；没有证据证明所有用户都受影响。详细证据见[调查报告](docs/investigation.zh-CN.md)。

## 下载与使用

1. 在本页面选择 **Code → Download ZIP**，解压到有写入权限的文件夹。不要直接在 ZIP 内运行。
2. 关闭 Gemini 窗口。
3. 双击 `Repair-Gemini.cmd`，查看修复结果。无需管理员权限；需要 Windows PowerShell 5.1 或更高版本。
4. 重新打开 Gemini，再关闭一次，确认后台进程退出；再次点击原来的图标，确认可以打开。

只检查是否适用，不修改客户端：

```powershell
powershell.exe -NoProfile -File .\Repair-Gemini.ps1 -CheckOnly
```

如果工具报告“新版程序代码已变化”，请停止，不要删除校验或强行修改哈希。如果仍失败，可在 Issues 提供客户端版本、Windows 版本和工具错误文字；不要上传账号数据、完整日志或 `app.asar`。

## 适用范围与保护措施

- 安装位置：`%LOCALAPPDATA%\Google\Gemini`，自动选择最高版本的 `app-x.y.z` 目录。
- 验证 `Gemini.exe` 的有效 Google LLC 数字签名，并校验程序包中的主文件。
- 仅接受已验证的完整 `main.js` SHA-256：见下面的哈希表。版本号相同但代码不同也会拒绝修改。
- Gemini 仍有窗口或日志没有显示进入退出清理时，拒绝修复，请先关闭窗口。
- 确认进入退出清理且没有主窗口后，可能结束该版本目录下残留的 Gemini 进程。
- 修改前备份原始程序包到工具目录的 `backups` 文件夹。
- 写入前再次检查程序包是否被自动更新替换；检测到变化就停止。

本工具修改客户端的程序包，不会清除账号、聊天记录或缓存，也不会打开诊断数据上传、关闭自动更新或安装后台监控。自动更新可能覆盖修复，届时可重新检查；未知新版会被拒绝。

## 修复原理

在诊断数据选项 `diagnosticConsent=false` 的退出分支，客户端在 `will-quit` 中阻止默认退出，清理辅助通信后同步调用 `app.quit()`。Electron 44.2.0 此时仍处于退出状态，会忽略这次调用，导致窗口已销毁而进程残留。

工具只在这段已确认的退出分支把 `app.quit()` 替换为等长的 `app.exit()`，同步更新 ASAR 内的完整性校验字段。完整主文件哈希必须匹配：

| 状态 | main.js SHA-256 |
| --- | --- |
| 原始已确认代码 | `c212c4d025dcff40209f80d48d9a8f11e87748b4024980f5443bf99c0015dd2c` |
| 修复后代码 | `67af484760f62b23a67bed3db4a689d143638127af94accf721717366dcff309` |

1.12.3 的原始程序包与 Google LLC 有效签名安装文件中的内容逐字节一致。这支持缺陷属于分发代码的结论。同代码、同运行时和同条件的其他用户可能受影响，这是代码推断，不是多台电脑实测。

## 恢复原版

关闭 Gemini 并确认进程完全退出。找到工具生成的 `backups\app-<版本>-<哈希>.original.asar`，仅在已安装版本与备份文件的版本一致时，将其复制到 `%LOCALAPPDATA%\Google\Gemini\app-<同一版本>\resources\app.asar` 覆盖修复文件。不要把旧版本备份覆盖到更新后的客户端。也可使用 Google 官方安装程序重新安装原版。

## English summary

A local workaround for a specific close/reopen failure in the official Google Gemini Windows client. After the main window closes, processes remain alive and launching the app again does not recreate the window.

- Reproduced and verified on one Windows x64 machine with Gemini 1.11.4 and 1.12.3. The affected population is unknown.
- The problematic `diagnosticConsent=false` shutdown branch calls `app.quit()` synchronously from a prevented `will-quit` callback. Electron 44.2.0 ignores that nested quit while it is already quitting.
- The tool changes this exact shutdown call to `app.exit()` and updates the ASAR integrity fields. It requires a valid Google executable signature and an exact known full-file hash; unknown code is rejected.
- Download **Code → Download ZIP**, extract, close Gemini, then run `Repair-Gemini.cmd`. The tool backs up the original package locally. Updates may replace the patch.
- `-CheckOnly` checks applicability without changing files. The repository contains only the tool and documentation, not Gemini binaries, settings, or user logs.

## License

The repair tool and original project documentation are provided under the [MIT License](LICENSE). Google Gemini and Electron remain subject to their respective licenses. No Google application binary is distributed here.
