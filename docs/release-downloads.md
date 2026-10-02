## Download and install

| Your computer | Download | How to install |
| --- | --- | --- |
| **Windows PC** | [**Download for Windows (.exe)**](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/01-Windows-ihatemeetings.exe) | Open the file and accept administrator permission. |
| **Mac — Apple Silicon or Intel** | [**Download for Mac (.dmg)**](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/02-Mac-ihatemeetings.dmg) | Open the disk image and drag **ihatemeetings** into **Applications**. |

## What's included

Version 1.5.3 keeps the main window size unchanged and fixes label spacing. The configuration windows are wider, with consistent columns, readable labels and room for long app paths. Windows scales the added controls with system DPI and no longer moves nested control internals. Long main-window details stay within their rows.

Configuration editing now pauses main-window interaction and hotkey starts. Preset switching validates before changing slots, stale inspector results cannot be applied to a different app, and Advanced Test ignores unused timer values. Check results remain visible instead of being overwritten by Ready.

The release pipeline measures actual native control bounds and font sizes, renders UI previews, and installs/reads back/removes app-scoped Windows WFP filters. Existing timing, random-range, parser, PF-syntax and packaging checks still run. These do not verify physical adapter behavior or every live Zoom/Meet setup.

The inspector displays app-owned connection metadata, not individual packet payloads. Mac application scoping remains based on observed connection tuples.

## Optional downloads — developers and advanced users

- [Source code and build instructions](https://github.com/daytondeltap/i-hate-online-meetings/blob/main/SOURCES.md)
- [All source](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/90-Source-All-platforms.zip)
- [Windows source](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/91-Source-Windows.zip)
- [Mac source](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/92-Source-Mac.zip)
- [Mac app ZIP](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/80-Mac-app-alternative.zip)
- [SHA256 checksums](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.3/99-SHA256SUMS.txt)
