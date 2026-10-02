## ihatemeetings 1.5

Downloads are built automatically for Windows x64 and universal macOS 12+ (Intel + Apple Silicon).

### Advanced mode
- Adds the requested **Advanced mode** checkbox at the top of both native UIs.
- Stores up to **five saved packet/flow presets**.
- Presets match a specific application plus optional protocol, direction, local port, remote IP/CIDR and remote port.
- Adds **Identify app traffic** so active TCP/UDP connection/socket metadata for the chosen app can be inspected and loaded into a preset.
- Advanced mode reuses the existing fixed/random timing, cycles, unlimited runs and hotkey controls.

### Platform behavior
- **Windows:** Advanced rules include the selected executable's WFP application identity, so another app using the same server/port is not included by that rule.
- **macOS:** Advanced mode discovers connections owned by the selected executable and installs exact PF rules for those connection tuples. It refreshes the app-owned connection set during held blocks.
- UDP socket tables may not expose a remote endpoint until the socket is connected. Encrypted payloads are not decrypted or inspected.

Existing Fast, Adapter, Zoom and Meet modes remain available. The release pipeline still runs timing tests, compiles the Windows app, compiles both Mac architectures, validates PF rule syntax, verifies the Mac bundle signature and verifies the DMG.
