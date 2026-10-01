# ihatemeetings

Native Windows and macOS network toggle utility, formerly NetToggle. The repository remains `zoom-breaker`.

[Download ready-to-run builds](https://github.com/daytondeltap/zoom-breaker/releases/latest).

- Windows: download `ihatemeetings.exe`, then launch and accept administrator permission.
- macOS: open the universal DMG and drag `ihatemeetings.app` to Applications.
- Source packages for each platform, an all-source archive, and SHA256 checksums are included in Releases.

Both versions include adapter/traffic modes, Zoom and Meet lag/hold modes, hotkeys, independent randomized OFF/ON ranges, and a compact native UI.

Windows Meet filtering combines browser identity with known media destinations. macOS Meet filtering covers those destinations for all apps on the selected adapter. A blocked call may remain joined. See the platform README files for exact scope and limitations.

Windows builds are unsigned. Mac builds are ad-hoc signed and not notarized. Live meeting behavior is not covered by build tests.
