The app is now **ihatemeetings**. The repository remains **zoom-breaker**.

Downloads:
- **ihatemeetings.exe** — compiled Windows x64 application.
- **ihatemeetings-1.4-macOS-universal.dmg** — macOS 12+ app for Intel and Apple Silicon. Open and drag the app to Applications.
- **ihatemeetings-1.4-macOS-app.zip** — the same Mac app without a DMG.
- **Windows-source.zip / macOS-source.zip / all-source.zip** — full source and build files.
- **SHA256SUMS.txt** — checksums for all downloads.

Adds Meet Lag and Meet Disconnect/hold, independent randomized OFF/ON ranges, compact native controls and the app icon. Retains automatic cycles, unlimited runs, manual hotkey toggling, Zoom modes and adapter modes.

Build verification: Windows timing tests and compilation; Mac timing/rule tests, PF syntax validation without loading rules, universal compilation, ad-hoc signature checks and DMG verification. Live UI, network adapters, administrator launch and real Zoom/Meet calls have not been verified by these automated checks.

Meet blocking affects known media destinations and does not guarantee removal from a meeting. Windows scopes it to supported browsers; macOS scopes it to all apps on the selected adapter. Mac Zoom state refresh may affect other connections to the same remote address.

Windows is unsigned. macOS is ad-hoc signed, not Apple-notarized; first launch may require System Settings → Privacy & Security → Open Anyway. Administrator permission is required.
