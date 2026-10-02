## Download and install

| Your computer | Download | How to install |
| --- | --- | --- |
| **Windows PC** | [**Download for Windows (.exe)**](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/01-Windows-ihatemeetings.exe) | Open the file and accept administrator permission. |
| **Mac — Apple Silicon or Intel** | [**Download for Mac (.dmg)**](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/02-Mac-ihatemeetings.dmg) | Open the disk image and drag **ihatemeetings** into **Applications**. |

## What's included

Version 1.5.2 tightens app-specific isolation on Mac: PF state removal now matches protocol and both complete endpoints, then removes only the matching state ID and creator ID. Shared UDP bindings with multiple owners are excluded. IPv4/IPv6 CIDR input validation is also stricter on both platforms. Five saved presets, the traffic inspector, timing modes and the expanded UI remain available.

The inspector displays app-owned TCP/UDP connection metadata, not individual packet payloads. Mac filtering uses observed connection tuples rather than kernel-enforced application identity, so socket reuse and discovery timing remain limitations. Windows rules include executable identity directly.

## Optional downloads — developers and advanced users

- [Source code and build instructions](https://github.com/daytondeltap/i-hate-online-meetings/blob/main/SOURCES.md)
- [All source](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/90-Source-All-platforms.zip)
- [Windows source](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/91-Source-Windows.zip)
- [Mac source](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/92-Source-Mac.zip)
- [Mac app ZIP](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/80-Mac-app-alternative.zip)
- [SHA256 checksums](https://github.com/daytondeltap/i-hate-online-meetings/releases/download/v1.5.2/99-SHA256SUMS.txt)
