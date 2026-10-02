## ihatemeetings 1.5.1

Downloads are built automatically for Windows x64 and universal macOS 12+ (Intel + Apple Silicon).

### UI spacing patch
- Expands the default Windows and macOS main windows so controls have more breathing room.
- Reflows the Advanced packet-filter editors on both platforms with wider fields, larger row gaps, and larger traffic-inspector areas.
- Keeps the same controls and behavior; this patch is focused on preventing UI overlap and clipped labels/inputs.
- Adds automated layout regression checks to the GitHub Actions pipeline so future builds validate minimum window size and the known control spacing before compilation/release.

### Advanced mode
- Keeps the **Advanced mode** checkbox at the top of both native UIs.
- Stores up to **five saved packet/flow presets**.
- Presets match a specific application plus optional protocol, direction, local port, remote IP/CIDR and remote port.
- **Identify app traffic** shows active TCP/UDP connection/socket metadata for the chosen app and can load it into a preset.
- Advanced mode reuses the existing fixed/random timing, cycles, unlimited runs and hotkey controls.

### Platform behavior
- **Windows:** Advanced rules include the selected executable's WFP application identity, so another app using the same server/port is not included by that rule.
- **macOS:** Advanced mode discovers connections owned by the selected executable and installs exact PF rules for those connection tuples. It refreshes the app-owned connection set during held blocks.
- UDP socket tables may not expose a remote endpoint until the socket is connected. Encrypted payloads are not decrypted or inspected.

Existing Fast, Adapter, Zoom and Meet modes remain available. The release pipeline runs timing tests, layout checks, compilation for both platforms, PF syntax validation, Mac signature verification, and DMG verification.
