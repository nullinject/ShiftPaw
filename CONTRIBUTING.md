# Contributing

感谢你改进 ShiftPaw。

## 开发流程

1. Fork 仓库并从 `main` 创建分支。
2. 保持改动聚焦，为行为变化补充测试。
3. 提交前运行 `swift test`，并用 `./scripts/build-app.sh` 验证应用包。
4. 提交 Pull Request，说明用户可见变化和验证结果。

## 仓库卫生

不要提交以下内容：

- `.build`、`DerivedData`、`.app`、`.dmg`、`.xcarchive` 或 `dSYM`
- 本地设置、日志、临时截图或测试中间产物
- 签名证书、公证凭据、令牌、环境文件或其他密钥
- 与当前实现无关的源码或生成文件

生成资源只有在应用运行所必需、来源清晰且可复现时才应提交。
