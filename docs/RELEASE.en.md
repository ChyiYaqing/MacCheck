# Release Guide

[中文](RELEASE.md) | **English**

## Version Number

The current version number is maintained in `Sources/App/Info.plist`:

- `CFBundleShortVersionString`: the public version number, e.g. `1.0`
- `CFBundleVersion`: the build number, e.g. `1`

Before releasing, update `VERSION` in `scripts/build_and_notarize.sh` to match.

## Local Packaging

```bash
./scripts/build_and_notarize.sh
```

Output file:

```text
~/Desktop/MacCheck-1.3.dmg
```

## Signing and Notarization

For official distribution you need:

1. An Apple Developer account
2. A `Developer ID Application` certificate installed in your keychain
3. Saved notarytool credentials

```bash
xcrun notarytool store-credentials "maccheck-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Optional environment variables:

```bash
export MACCHECK_SIGN_ID="Developer ID Application: Your Name (TEAMID)"
export MACCHECK_NOTARY_PROFILE="maccheck-notary"
```

## GitHub Release

```bash
gh release create v1.3 ~/Desktop/MacCheck-1.3.dmg \
  --repo andyhuo520/MacCheck \
  --title "MacCheck 1.3" \
  --notes "首次发布：本地 Mac 验机、交互测试、报告导出。"
```

(The `--notes` text above reads: "First release: local Mac inspection, interactive tests, report export.")

## Post-Release Checklist

- The DMG attachment is visible on the Release page
- `hdiutil verify` passes on the downloaded DMG
- The app launches and completes the home-screen scan
- The install and usage instructions in the README are still accurate

## Troubleshooting User Installs

If macOS Gatekeeper blocks a user the first time they open an ad-hoc or non-notarized build, first suggest right-clicking `MacCheck.app` and choosing "Open".

To make the "Anywhere" option appear in System Settings, run in Terminal:

```bash
sudo spctl --master-disable
```

If the app is reported as "damaged and can't be opened", and you have confirmed the app comes from a trusted source and is in `/Applications`, run:

```bash
sudo xattr -rd com.apple.quarantine /Applications/MacCheck.app
```
