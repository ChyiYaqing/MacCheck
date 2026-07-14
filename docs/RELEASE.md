# 发布说明

## 版本号

当前版本号在 `Sources/App/Info.plist` 中维护：

- `CFBundleShortVersionString`: 对外版本号，例如 `1.0`
- `CFBundleVersion`: 构建号，例如 `1`

发布前请同步更新 `scripts/build_and_notarize.sh` 中的 `VERSION`。

## 本地打包

```bash
./scripts/build_and_notarize.sh
```

输出文件：

```text
~/Desktop/MacCheck-1.0.dmg
```

## 签名和公证

如需正式分发，需要：

1. Apple Developer 账号
2. 钥匙串中安装 `Developer ID Application` 证书
3. 保存 notarytool 凭证

```bash
xcrun notarytool store-credentials "maccheck-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

可选环境变量：

```bash
export MACCHECK_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export MACCHECK_NOTARY_PROFILE="maccheck-notary"
```

## GitHub Release

```bash
gh release create v1.0 ~/Desktop/MacCheck-1.0.dmg \
  --repo andyhuo520/MacCheck \
  --title "MacCheck 1.0" \
  --notes "首次发布：本地 Mac 验机、交互测试、报告导出。"
```

## 发布后检查

- Release 页面能看到 DMG 附件
- 下载 DMG 后 `hdiutil verify` 通过
- App 可以启动并完成首页扫描
- README 中的安装和使用说明仍然准确
