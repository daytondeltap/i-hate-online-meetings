IHATEMEETINGS 1.5.1 - WINDOWS 10/11 x64

RUN
Open ihatemeetings.exe and accept the administrator prompt. No compiler, Python,
Electron, .NET download, or separate runtime installation is required.

UI SPACING
Version 1.5.1 expands the main window and Advanced editor and increases spacing
between the existing controls to prevent the overlap/clipping reported in 1.5.0.
The release build also runs automated checks for the known layout gaps before
compilation.

ADVANCED MODE
Check Advanced mode at the top of the window, then choose Configure.
There are five saved presets. Each preset can match:
- one executable/application
- Any, TCP, or UDP
- Both, Outbound, or Inbound direction
- optional local port
- optional remote IPv4/IPv6 address or CIDR
- optional remote port

Identify app traffic shows active TCP connections and UDP sockets owned by the
selected executable. Select an observed connection and choose Use selected
connection to load its protocol, ports, and remote address into the preset.
Windows' UDP socket table does not expose a remote endpoint for unconnected UDP
sockets, so those rows show only the local socket.

Advanced mode uses the same Automatic/Manual behavior, OFF/ON timing, random
ranges, cycle count, Until stopped, limit and hotkey controls as the base modes.
Windows Filtering Platform rules include the executable application identity, so
another executable using the same remote address/port is not included by that
preset. Encrypted payload contents are not decrypted or inspected.

BASE MODES
Fast mode: temporarily blocks IPv4/IPv6 traffic on the selected adapter.
Adapter mode: disables/enables the selected network device using Windows APIs.
Zoom Lag: cycles between blocking and allowing the local desktop Zoom client.
Zoom Kick: holds the local Zoom client's networking blocked until restored.
Meet Lag: cycles supported browsers' connections to known Meet media ranges.
Meet Disconnect: holds those media connections blocked until restored.

Start/Stop buttons and hotkeys remain available. Ctrl+Alt+F12 requests
restoration. Closing the app requests restoration. Dynamic WFP filters expire
with the process. Existing adapter crash recovery remains in place.

TEST BUTTON
Performs an install/remove API check for the selected base mode or Advanced
preset and restores state. It does not prove a live call lost packets.

FILES / PREFERENCES
Preferences and capped errors.log: %LOCALAPPDATA%\ihatemeetings\.
To remove ihatemeetings: close it, delete the app and optionally that preferences
folder. Previous releases remain in GitHub release history.
