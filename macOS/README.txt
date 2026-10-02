ihatemeetings 1.5.1 — macOS 12 or newer, Intel and Apple Silicon

INSTALL
Download the universal DMG from Releases, open it, and drag ihatemeetings.app
to Applications. Launch the app and approve its administrator prompt.

UI SPACING
Version 1.5.1 expands and reflows the main window and Advanced editor so controls
have larger horizontal and vertical gaps. The build pipeline validates the known
layout geometry before compiling the universal app.

ADVANCED MODE
Check Advanced mode at the top, then choose Configure. Five persistent presets
are available. Each can match one selected application executable plus Any/TCP/
UDP, Both/Outbound/Inbound direction, optional local port, remote IP/CIDR and
optional remote port.

Identify app traffic uses the selected running application and lsof to show its
active TCP/UDP connection/socket metadata. A selected connection can populate
the preset. Unconnected UDP sockets may not expose a remote endpoint.

macOS PF does not attach a process identity to ordinary PF rules. To keep the
preset app-specific, ihatemeetings first discovers connections owned by the
selected executable and then installs exact rules for those connection tuples.
Held Advanced blocks refresh the selected app's matching connection set. Other
apps are not intentionally added merely because they contact the same server.
Encrypted payload contents are not decrypted or inspected.

Advanced mode uses the same Automatic/Manual behavior, timing, random ranges,
cycles, Until stopped, limit and hotkey controls as the base modes.

BASE MODES
Fast blocks adapter traffic. Adapter toggles the adapter device itself.
Zoom Lag cycles detected desktop Zoom connections; Zoom Kick holds them blocked.
Meet Lag cycles published Meet media ranges; Meet Disconnect holds them blocked.

The app uses its existing private com.apple/* PF anchor and restoration helper.
The Test button performs local command/rule checks and restores state; it does
not verify live call packet loss.

DEVELOPERS
bash macOS/build.sh from repo root (requires Apple developer tools).
source/main_advanced.swift contains the native UI/networking implementation;
source/prepare_layout.pl generates the expanded 1.5.1 build layout.
source/Timing.swift contains timing and Meet range helpers.
