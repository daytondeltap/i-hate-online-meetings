ihatemeetings 1.4 — macOS 12 or newer, Intel and Apple Silicon

INSTALL
Download the universal DMG from Releases, open it, and drag ihatemeetings.app
to Applications. Launch the app and approve its administrator prompt.
No compiler, Terminal build or external runtime is required to use the app.
The app is ad-hoc signed, not Apple-notarized. If blocked on first launch,
use System Settings > Privacy & Security > Open Anyway after trying to open it.
Close older NetToggle / ihatemeetings instances first.

CONTROLS
Select your Ethernet / Wi-Fi adapter. The default-route adapter is preselected.
Fast blocks adapter traffic. Adapter toggles the adapter device itself.
Zoom Lag cycles detected desktop Zoom connections; Zoom Kick holds them blocked.
Meet Lag cycles published Meet media ranges; Meet Disconnect holds them blocked.
Automatic repeats OFF then ON. Manual hotkey toggles OFF / ON without cycles.
F6, Control+F6, Option+F6, Control+Option+F6 and F7 are available.
Random ranges select an independent inclusive integer each OFF and ON phase.
Times are milliseconds; 10..86400000. Count or Until stopped; limit 0 = none.
Closing or stopping requests restoration; a separate helper attempts crash recovery.
The UI is 390 x 350 points. Settings persist in the elevated app's preferences.

SCOPE
Meet filtering uses destination ranges on the selected interface, for ALL apps.
It is not browser- or tab-specific on macOS. It includes IPv4 and IPv6 and TCP
fallback. Chat/signaling may continue and the meeting may remain joined.
Neither Zoom Kick nor Meet Disconnect guarantees a meeting-server kick.
PF states matching local/remote address pairs are refreshed when blocking.
For Zoom this can affect other connections to the same remote address; Meet
refreshes local-address/Meet-range pairs; Fast refreshes the adapter addresses.
Zoom discovery depends on active connected sockets and may miss unconnected UDP.
VPNs/proxies or changed media endpoints may reduce coverage. Zoom Hold refreshes
its socket list about every 700ms; timing includes command overhead.
This app only uses a private com.apple/* PF anchor. It refuses to run if the
active system PF configuration does not invoke that anchor namespace.
It does not replace /etc/pf.conf or flush all system firewall state.

TESTING
The Test button performs local command/rule checks and restores state. It does
not verify call packet loss. Build checks compile both Mac architectures, run
timing tests, parse Meet PF rules without loading them, verify signatures and DMG.
Live UI, administrator launch, hotkey, adapter and call behavior need testing on
your own Mac; no live Zoom/Meet call test was performed in the build pipeline.

DEVELOPERS
bash macOS/build.sh from repo root (requires Apple developer tools).
source/main.swift: AppKit UI and networking. source/Timing.swift: timing and ranges.
tests/main.swift: timing/rule tests. No build command is needed by end users.
