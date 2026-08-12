# ShiftPaw · 班次喵

<p align="center">
  <img src="branding/shiftpaw-icon.svg" width="128" height="128" alt="ShiftPaw icon">
</p>

<p align="center"><strong>一只会巡游的桌面排班提醒猫</strong></p>

ShiftPaw 是一个原生 macOS 排班提醒与桌面宠物应用。它支持白班、夜班和跨日交接班次，小猫会在桌面可见区域内巡游，并在每经过一小时后卖萌一次。

## 功能

- 白班、夜班和跨日交接模板，支持编辑班次时间。
- 当前时间、值守状态、下一提醒和倒计时集中显示。
- 透明桌面小猫可自动巡游、手动拖动和隐藏。
- 每小时一次卖萌动画，双击桌宠可打开班次面板。
- 无声音系统通知、菜单栏驻留、始终置顶和登录时启动。
- 自动恢复主窗口和桌宠位置，并校验持久化设置。

## 系统要求

- macOS 14 Sonoma 或更高版本
- 从源码构建需要 Swift 6 和匹配版本的 Xcode/macOS SDK

## 从源码运行

```bash
git clone https://github.com/nullinject/ShiftPaw.git
cd ShiftPaw
swift test
swift run ShiftPaw
```

## 构建 macOS 应用

```bash
./scripts/build-app.sh
open ".build/app/ShiftPaw.app"
```

脚本默认执行本地临时签名。发布构建应通过环境变量传入 Developer ID Application 证书：

```bash
CODESIGN_IDENTITY="Developer ID Application: Example Corp (TEAMID)" \
APP_VERSION="1.0.0" BUILD_NUMBER="1" ./scripts/build-app.sh
```

正式分发还需要完成 Apple 公证与 stapling。签名证书、公证凭据和生成的应用包不应提交到仓库。

## 本地数据

设置保存在：

```text
~/Library/Application Support/ShiftPaw/settings.json
```

ShiftPaw 不需要网络连接，不收集或上传用户数据。

## 参与贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请遵循 [SECURITY.md](SECURITY.md) 中的报告方式。

## 许可证

[MIT License](LICENSE)
