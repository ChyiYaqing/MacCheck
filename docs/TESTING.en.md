# MacCheck Testing Checklist

[中文](TESTING.md) | **English**

This document is for pre-release self-testing and for reviewing the in-store inspection workflow. Automatic checks can be verified by building and launching the app; interactive tests require real Mac hardware.

## Pre-Release Basic Verification

```bash
xcodebuild -project MacCheck.xcodeproj -scheme MacCheck -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build_release CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
./scripts/build_and_notarize.sh
hdiutil verify ~/Desktop/MacCheck-1.3.dmg
```

Verify that:

- The app launches normally and the home-screen scan completes
- Every page in the sidebar opens without obvious cramped layouts or blank areas
- "Save to History" creates a history entry
- "Export Report" exports both PNG and PDF
- The DMG mounts and contains `MacCheck.app` and an Applications shortcut

## Automatic Checks

| Module | Expected Result |
| --- | --- |
| Hardware Specs | Shows model, serial number, chip, memory, architecture, macOS version |
| Battery | Laptops show cycle count and health info; desktops show not applicable or no data |
| Security & Lock | Shows security chip, MDM, and Apple ID / Activation Lock hints |
| Storage | Shows capacity, free space, and SMART or disk status |
| Network | Shows Wi-Fi / Bluetooth status |
| Ports | Shows detected USB / Thunderbolt controllers or devices |
| AI Models | Gives local-model suitability suggestions based on memory |

## Interactive Tests

| Module | Action | Pass Criteria |
| --- | --- | --- |
| Keyboard | Enter full screen and press each physical key | Pressed keys highlight; no dead, repeating, or sticky keys |
| Display | Switch between solid-color, grayscale, and checkerboard patterns | No obvious dead pixels, bright spots, backlight bleed, or banding |
| Speakers / Headphones | Play the test tone | Left/right channels and headphone output work correctly |
| Microphone | After granting permission, record or watch the level meter | Steady input with no abnormal background noise |
| Camera | After granting permission, view the preview | Clear image with no obstruction, dead pixels, or flicker |
| Touch ID | Follow the on-screen prompts | Works, or clearly reports that it is not supported |
| Trackpad | Test clicks, swipes, and gestures | Clicking, moving, and scrolling respond normally |
| Stress Test | Start a short stress test | No freezes and no temperature/performance red flags |
| Disk Speed | Start read/write sampling | Read/write results are displayed with no unexpected failures |
| Port-by-Port Test | Plug in and remove peripherals and record results | All target ports recognize peripherals |

## Privacy and Screenshots

Real screenshots and reports usually contain the serial number, device name, OS version, and similar details. Redact them before publishing to GitHub, a website, or social media.

The images in this repository's `docs/assets` are screenshots from real devices, with serial numbers and other sensitive details redacted.
