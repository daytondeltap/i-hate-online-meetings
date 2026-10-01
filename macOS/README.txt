NetToggle 1.3 for macOS
========================

Build:
1. Double-click INSTALL-NETTOGGLE.command.
2. If Apple Command Line Tools are missing, macOS will open their installer. Complete it and run the file again.
3. The finished disk image is written to: dist/NetToggle-1.3-macOS.dmg

Runtime:
- The app requests administrator permission once per launch because interface state and macOS pf rules require it.
- Fast mode temporarily blocks traffic on the selected interface through the com.apple/nettoggle pf anchor.
- Adapter mode uses ifconfig down/up and includes a crash guard that attempts to bring the interface back up.
- pf-backed modes include a separate crash guard that clears the NetToggle anchor and releases NetToggle's pf enable token if the app exits unexpectedly.
- Zoom Lag discovers the local Zoom processes' active TCP/UDP connection tuples and intermittently blocks those exact connections.
- Zoom Kick refreshes those Zoom connection tuples while running and keeps them blocked until Stop/restore is used.
- Zoom-specific modes do not send traffic to, modify, or control other participants' computers.

Notes:
- This source build is ad-hoc signed, not Apple-notarized. Gatekeeper may require Control-click > Open on first launch.
- Zoom changes its processes/endpoints over time, so the app refreshes active connections while Zoom Kick is running.

EASY INSTALL (v1.3 builder update)
INSTALL-NETTOGGLE.command now builds the app, creates the DMG, installs NetToggle.app
into /Applications (asks for your password if needed), clears the quarantine flag and launches it.
If macOS blocks the script: right-click it > Open, or in Terminal run:  bash INSTALL-NETTOGGLE.command
