# Portal Screen Mirror

Mirror any screen, individual window, or rectangular region onto another display through XDG `ScreenCast` and a click-through `zwlr-layer-shell-v1` overlay surface — no compositor window rules required.

## Plugin

| Field | Value |
| --- | --- |
| ID | `fumoctl/portal-screen-mirror` |
| Entries | Bar widget: `mirror`; panel: `controls`; layer: `display`; service: `mirror-service`; shortcut: `toggle` |

## Requirements

- `python3` with `PyGObject` (`gi`) and GStreamer 1.0 (`gstreamer`, `gst-plugins-base`, `gst-plugins-good`, and the PipeWire GStreamer plugin `libgstpipewire`)
- `slurp` on `PATH` for rectangular region selection
- `xdg-desktop-portal` with an active `org.freedesktop.portal.ScreenCast` backend (such as `xdg-desktop-portal-umbriel`, `xdg-desktop-portal-hyprland`, `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gnome`, or `xdg-desktop-portal-kde`) and `pipewire`

## Usage

Enable `fumoctl/portal-screen-mirror` in **Settings → Plugins**, then add the `mirror` bar widget to your bar (`type = "fumoctl/portal-screen-mirror:mirror"`) or add the `toggle` tile to Control Center shortcuts.

Clicking the bar widget opens the two-step `controls` panel:

1. Select the **destination screen** (external, unfocused displays such as `HDMI-A-1` sort ahead of `eDP-*` laptop panels).
2. Click **Portal Picker (Screen or Window)** to choose any monitor or window via your desktop portal, or **Rectangular Region** to drag a crop box with `slurp`.

While mirroring is active, right-clicking the bar widget (or clicking **Stop Mirroring** inside the panel) stops the stream immediately.

Open or close the panel directly from the command line or a compositor keybind with:

```sh
noctalia msg panel-toggle fumoctl/portal-screen-mirror:controls
```

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `show_cursor` | `bool` | `true` | Embeds the pointer cursor in newly started `ScreenCast` streams (`cursor_mode = 2`). |
| `fit` | `select` | `"contain"` | Controls how the stream scales inside the destination output (`contain`, `cover`, or `stretch`). |

## IPC

Address the `mirror-service` entry with the `all` target for keybind workflows:

```sh
# Toggle: stops an active mirror, or opens the destination + source panel
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all toggle

# Start portal or region mode directly (optional connector name; defaults to first external output)
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all portal HDMI-A-1
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all region HDMI-A-1

# Stop an active mirror
noctalia msg plugin fumoctl/portal-screen-mirror:mirror-service all stop
```

## Notes

- **Compositor compatibility**: Because frames render into a plugin-owned `zwlr-layer-shell-v1` `overlay` surface configured dynamically on the target connector (`noctalia.layer.configure`), mirroring works even on compositors that ignore `xdg_toplevel.set_fullscreen` target output hints (such as Umbriel). On wlroots compositors implementing `zwlr_screencopy_manager_v1`, **Rectangular Region** mode captures the `slurp` box directly without opening a second portal picker dialog (falling back to XDG `ScreenCast` + `videocrop` elsewhere).
- **Processes spawned**: `service.luau` launches bundled `companion.py`, which invokes `slurp` only when **Rectangular Region** mode is selected.
- **Filesystem writes**: Writes transient session coordination files (`mirror.run` and `stream.sock`) and per-output portal restore tokens (`restore_tokens.json`, mode `0600`) solely inside `noctalia.pluginDataDir()`.
- **Network**: Makes zero network requests; all communication stays local over session D-Bus, PipeWire, and an owner-only (`0600`) Unix `SOCK_SEQPACKET` socket.
