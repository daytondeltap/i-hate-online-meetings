IHATEMEETINGS 1.4 - WINDOWS 10/11 x64

RUN
Open ihatemeetings.exe and accept the administrator prompt. No compiler, Python,
Electron, .NET download, or separate runtime installation is required.
Close older ihatemeetings instances before launching. The binary is unsigned.

MODES
Fast mode: temporarily blocks IPv4/IPv6 traffic on the selected adapter.
Adapter mode: disables/enables the selected network device using Windows APIs.
Zoom Lag: cycles between blocking and allowing the local desktop Zoom client.
Zoom Kick: holds the local Zoom client's networking blocked until restored.
Meet Lag: cycles between blocking and allowing supported browsers' connections
  to the published Google Meet media ranges.
Meet Disconnect: holds those media connections blocked until restored.

App-targeted modes do not use the adapter dropdown. They apply across adapters.
Lag modes use automatic cycles. Zoom Kick / Meet Disconnect use manual hold.
Fast / Adapter modes support either Automatic or Manual via the next dropdown.
Start/Stop buttons and hotkeys remain available. Ctrl+Alt+F12 requests restoration.
Closing the app requests restoration. Dynamic WFP filters expire with the process.
Adapter mode retains the recovery helper supplied in version 1.3.

GOOGLE MEET SCOPE
Start Chrome, Edge, Firefox, Brave, Opera or Vivaldi with your Meet call before
starting a Meet mode. The app finds the running browser executable paths and
requires BOTH browser identity and a known Meet media destination for a block.
It never intentionally blocks all browser traffic. Browser updates/new browser
paths require stopping and restarting the mode so detection can run again.

This is a media-connection filter, not a browser-tab filter or a Meet API control.
It can affect other Meet calls or Meet streams in those browsers. Signaling,
chat, the meeting page and shared Google web services are not broadly blocked.
Meet may remain joined, show reconnecting, or adapt to packet loss. Neither Meet
Disconnect nor Zoom Kick guarantees a service-side kick/removal from a meeting.
VPN/proxy routing, alternative endpoints and future Google network changes may
reduce coverage. No decrypted packet inspection is performed.

Google's published media ranges, checked 2026-10-01:
IPv4: 74.125.250.0/24; 74.125.247.128/32; 142.250.82.0/24.
IPv6: 2001:4860:4864:5::/64; 2001:4860:4864:4:8000::/128;
      2001:4860:4864:6::/64.
Both address families and both connection directions are covered by ALE filters.
No port restriction is used within these ranges, covering TCP media fallback.
Source:
https://knowledge.workspace.google.com/admin/meet/prepare-your-network-for-meet-meetings-and-live-streams

TIMING
All values are milliseconds. With Random timing unchecked, Min/fixed is the
fixed duration and Max is ignored. With it checked, a new independent integer
is selected uniformly from the inclusive Min..Max range for EVERY OFF/ON phase.
Example: OFF 200..700 ms and ON 1000..3000 ms.
Each bound must be 10..86400000 ms; Max must be at least Min. Equal bounds work
as a fixed interval. Values are validated before any switching occurs.
Random ranges work with all automatic modes, including Zoom Lag and Meet Lag.
Manual hold modes ignore all timing, repeat and duration controls.

One cycle = OFF then ON. Count, Until stopped and Limit seconds behave as before.
0 seconds means no time limit; the first applicable limit stops the run.
A duration deadline may truncate a sampled interval. Stop interrupts waits.
Durations start after Windows accepts each transition, so real cadence includes
API and driver overhead. Adapter reconnects can take seconds.

COMPACT UI
The window's client layout is 280 x 278 dialog units (about 28% less area than
1.3). The native 9-point font, icon, tab navigation, settings and hotkeys remain.
DPI scaling affects the actual pixel size. Adapter names have a wider dropdown.

TEST BUTTON
Performs an OFF/ON API/filter read-back test and restores state. The result
is labeled API/filter checks; it does not prove a live Meet/Zoom call lost packets.
Cancellation is reported separately from a completed test. Try in a test meeting
to check your own browser/network behavior. No live Windows meeting tests were
possible in the build environment.

FILES / PREFERENCES
Preferences and capped errors.log: %LOCALAPPDATA%\ihatemeetings\.
The new random timing checkbox and both maximums persist alongside older settings.
Source and icon: source\. Build helpers are optional because ihatemeetings.exe is
included. Previous versions remain available in repository release history.
To remove ihatemeetings: close it, delete its folder and optional preferences folder.
