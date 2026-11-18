{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  umbrielBin = lib.getExe config.programs.umbriel.package;
  mirrorOutputs =
    map (n: "HDMI-A-${toString n}") (lib.range 1 4)
    ++ map (n: "DP-${toString n}") (lib.range 1 10)
    ++ map (n: "eDP-${toString n}") (lib.range 1 2);

  # XDG ScreenCast portal -> Wayland fullscreen mirror client.
  # Opens Umbriel's native `UmbrielSharePicker` (Screens + Windows thumbnails,
  # plus dynamic source switching) and renders the PipeWire DMA-BUF/SHM stream
  # onto `<dest>` via GStreamer `waylandsink` (`app_id = dev.ultix.ScreenMirror.<dest>`).
  portalMirror =
    let
      pyEnv = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
      typelibPath = lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.glib.out
        pkgs.gst_all_1.gstreamer.out
      ];
      gstPluginPath = lib.makeSearchPath "lib/gstreamer-1.0" [
        pkgs.pipewire
        pkgs.gst_all_1.gstreamer.out
        pkgs.gst_all_1.gst-plugins-base
        pkgs.gst_all_1.gst-plugins-bad
      ];
      runtimeBinPath = lib.makeBinPath [
        config.programs.umbriel.package
        pkgs.libnotify
      ];
      script = pkgs.writeText "portal-mirror.py" ''
        import json
        import os
        import signal
        import subprocess
        import sys

        import gi
        gi.require_version("Gst", "1.0")
        from gi.repository import Gio, GLib, Gst


        def notify(body: str, urgent: bool = False) -> None:
            cmd = ["notify-send", "-a", "Screen Mirror"]
            if urgent:
                cmd += ["-u", "critical"]
            cmd += ["Screen Mirror", body]
            subprocess.run(cmd, check=False)


        def main() -> int:
            if len(sys.argv) < 2:
                sys.stderr.write("Usage: portal-mirror <dest-output> [source-types]\n")
                return 1

            dest = sys.argv[1]
            source_types = int(sys.argv[2]) if len(sys.argv) > 2 else 3

            pidfile = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "screen-mirror.pid")
            my_pid = str(os.getpid())
            try:
                with open(pidfile, "w", encoding="utf-8") as f:
                    f.write(my_pid + "\n")
            except OSError:
                pass

            def clear_pidfile() -> None:
                try:
                    with open(pidfile, "r", encoding="utf-8") as f:
                        if f.read().strip() == my_pid:
                            os.remove(pidfile)
                except OSError:
                    pass

            # Set Wayland app_id before Gst.init() so waylandsink maps directly onto
            # `dest` via Umbriel's `dev.ultix.ScreenMirror.<output>` window rule.
            GLib.set_prgname(f"dev.ultix.ScreenMirror.{dest}")
            Gst.init(None)

            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            unique = bus.get_unique_name()
            if not unique:
                clear_pidfile()
                notify("D-Bus session unavailable", urgent=True)
                return 1

            sender = unique.lstrip(":").replace(".", "_")
            seq = 0
            session_handle = None
            closed_sub = 0
            pw_fd = None
            pipeline = None
            watch_proc = None

            def close_session() -> None:
                nonlocal session_handle
                if session_handle:
                    handle = session_handle
                    session_handle = None
                    try:
                        bus.call_sync(
                            "org.freedesktop.portal.Desktop",
                            handle,
                            "org.freedesktop.portal.Session",
                            "Close",
                            None,
                            None,
                            Gio.DBusCallFlags.NONE,
                            2000,
                            None,
                        )
                    except GLib.Error:
                        pass

            def portal_request(
                method: str,
                prefix: list[GLib.Variant],
                options: dict[str, GLib.Variant],
            ) -> tuple[int, dict]:
                nonlocal seq
                seq += 1
                token = f"ultix_mirror_{os.getpid()}_{seq}"
                expected_path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
                box: dict = {}
                req_loop = GLib.MainLoop()

                def on_resp(_conn, _sender, _path, _iface, _sig, sig_params):
                    resp, res = sig_params.unpack()
                    box["resp"] = resp
                    box["res"] = res
                    req_loop.quit()

                def on_abort():
                    box.setdefault("resp", 1)
                    req_loop.quit()
                    return GLib.SOURCE_CONTINUE

                sub_id = bus.signal_subscribe(
                    "org.freedesktop.portal.Desktop",
                    "org.freedesktop.portal.Request",
                    "Response",
                    expected_path,
                    None,
                    Gio.DBusSignalFlags.NONE,
                    on_resp,
                )
                sig_ids = [
                    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, on_abort)
                    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
                ]
                try:
                    opts = dict(options)
                    opts["handle_token"] = GLib.Variant("s", token)
                    call_args = GLib.Variant.new_tuple(*prefix, GLib.Variant("a{sv}", opts))
                    ret = bus.call_sync(
                        "org.freedesktop.portal.Desktop",
                        "/org/freedesktop/portal/desktop",
                        "org.freedesktop.portal.ScreenCast",
                        method,
                        call_args,
                        GLib.VariantType.new("(o)"),
                        Gio.DBusCallFlags.NONE,
                        -1,
                        None,
                    )
                    actual_path = ret.get_child_value(0).get_string()
                    extra_sub = 0
                    if actual_path != expected_path and "resp" not in box:
                        extra_sub = bus.signal_subscribe(
                            "org.freedesktop.portal.Desktop",
                            "org.freedesktop.portal.Request",
                            "Response",
                            actual_path,
                            None,
                            Gio.DBusSignalFlags.NONE,
                            on_resp,
                        )
                    try:
                        if "resp" not in box:
                            req_loop.run()
                    finally:
                        if extra_sub:
                            bus.signal_unsubscribe(extra_sub)
                finally:
                    bus.signal_unsubscribe(sub_id)
                    for s in sig_ids:
                        GLib.source_remove(s)

                return box.get("resp", 2), box.get("res", {})

            try:
                resp, res = portal_request(
                    "CreateSession",
                    [],
                    {"session_handle_token": GLib.Variant("s", f"ultix_sess_{os.getpid()}")},
                )
                if resp != 0 or "session_handle" not in res:
                    if resp != 1:
                        notify("Failed to create ScreenCast portal session", urgent=True)
                    return 0 if resp == 1 else 1

                session_handle = str(res["session_handle"])

                resp, _ = portal_request(
                    "SelectSources",
                    [GLib.Variant("o", session_handle)],
                    {
                        "types": GLib.Variant("u", source_types),
                        "multiple": GLib.Variant("b", False),
                        "cursor_mode": GLib.Variant("u", 2),
                    },
                )
                if resp != 0:
                    return 0 if resp == 1 else 1

                resp, res = portal_request(
                    "Start",
                    [GLib.Variant("o", session_handle), GLib.Variant("s", "")],
                    {},
                )
                if resp != 0:
                    return 0 if resp == 1 else 1

                streams = res.get("streams") or []
                if not streams:
                    notify("No ScreenCast stream selected", urgent=True)
                    return 1

                node_id = int(streams[0][0])

                fd_ret, fd_list = bus.call_with_unix_fd_list_sync(
                    "org.freedesktop.portal.Desktop",
                    "/org/freedesktop/portal/desktop",
                    "org.freedesktop.portal.ScreenCast",
                    "OpenPipeWireRemote",
                    GLib.Variant("(oa{sv})", (session_handle, {})),
                    GLib.VariantType.new("(h)"),
                    Gio.DBusCallFlags.NONE,
                    -1,
                    None,
                    None,
                )
                fd_idx = fd_ret.get_child_value(0).get_handle()
                pw_fd = fd_list.get(fd_idx)

                main_loop = GLib.MainLoop()

                # Negotiate `video/x-raw` (PipeWire MemFd SHM) rather than `memory:DMABuf`:
                # `xdg-desktop-portal-umbriel` exports multi-plane AMD DCC DMA-BUFs with a
                # dummy `chunk->size = 9`, which GStreamer's `waylandsink` fails to import
                # (`eglCreateImageKHR` -> `EGL_BAD_MATCH`), leaving the output black.
                pipeline = Gst.parse_launch(
                    "pipewiresrc name=src always-copy=true do-timestamp=true keepalive-time=100 resend-last=true "
                    "! video/x-raw,format={BGRx,BGRA,RGBx,RGBA} "
                    "! videoconvert "
                    "! queue max-size-buffers=1 leaky=downstream "
                    "! waylandsink name=sink sync=false"
                )
                src_elem = pipeline.get_by_name("src")
                src_elem.set_property("fd", pw_fd)
                src_elem.set_property("path", str(node_id))
                if src_elem.find_property("on-disconnect") is not None:
                    Gst.util_set_object_arg(src_elem, "on-disconnect", "eos")

                gst_bus = pipeline.get_bus()
                gst_bus.add_signal_watch()

                def on_gst_msg(_bus, msg):
                    if msg.type == Gst.MessageType.EOS:
                        main_loop.quit()
                    elif msg.type == Gst.MessageType.ERROR:
                        err, _dbg = msg.parse_error()
                        notify(f"Mirror stream error: {err.message}", urgent=True)
                        main_loop.quit()

                gst_bus.connect("message", on_gst_msg)

                closed_sub = bus.signal_subscribe(
                    "org.freedesktop.portal.Desktop",
                    "org.freedesktop.portal.Session",
                    "Closed",
                    session_handle,
                    None,
                    Gio.DBusSignalFlags.NONE,
                    lambda *_args: main_loop.quit(),
                )

                watch_proc = Gio.Subprocess.new(
                    ["umbriel", "subscribe", "outputs"],
                    Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE,
                )
                watch_stream = Gio.DataInputStream.new(watch_proc.get_stdout_pipe())

                def read_next_output_event() -> None:
                    watch_stream.read_line_async(GLib.PRIORITY_DEFAULT, None, on_output_event)

                def on_output_event(stream: Gio.DataInputStream, result: Gio.AsyncResult) -> None:
                    try:
                        line, _length = stream.read_line_finish_utf8(result)
                    except GLib.Error:
                        return
                    if line is None:
                        return
                    try:
                        out = subprocess.check_output(["umbriel", "outputs", "--json"], text=True, timeout=2)
                        names = [o.get("name") for o in json.loads(out) if o.get("enabled") is True]
                        if dest not in names:
                            main_loop.quit()
                            return
                    except Exception:
                        pass
                    read_next_output_event()

                read_next_output_event()

                main_sigs = [
                    GLib.unix_signal_add(
                        GLib.PRIORITY_DEFAULT,
                        sig,
                        lambda: main_loop.quit() or GLib.SOURCE_CONTINUE,
                    )
                    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)
                ]

                try:
                    if pipeline.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
                        notify(f"Failed to start portal mirror on {dest}", urgent=True)
                        return 1
                    notify(f"Mirroring selection → {dest}")
                    main_loop.run()
                finally:
                    for s in main_sigs:
                        GLib.source_remove(s)

                return 0
            except GLib.Error as err:
                notify(f"Portal error: {err.message}", urgent=True)
                return 1
            finally:
                if watch_proc is not None:
                    try:
                        watch_proc.force_exit()
                    except Exception:
                        pass
                if pipeline is not None:
                    b = pipeline.get_bus()
                    if b is not None:
                        b.remove_signal_watch()
                    pipeline.set_state(Gst.State.NULL)
                    pipeline = None
                if closed_sub:
                    bus.signal_unsubscribe(closed_sub)
                close_session()
                if pw_fd is not None:
                    try:
                        os.close(pw_fd)
                    except OSError:
                        pass
                clear_pidfile()


        if __name__ == "__main__":
            sys.exit(main())
      '';
    in
    pkgs.runCommandLocal "portal-mirror"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        ${pyEnv}/bin/python3 -m py_compile ${script}
        mkdir -p "$out/bin"
        makeWrapper "${pyEnv}/bin/python3" "$out/bin/portal-mirror" \
          --add-flags "${script}" \
          --set GI_TYPELIB_PATH "${typelibPath}" \
          --set GST_PLUGIN_SYSTEM_PATH_1_0 "${gstPluginPath}" \
          --prefix PATH : "${runtimeBinPath}"
      '';

  # Unified Umbriel screen mirror controller supporting:
  # - Specific Window or Full Screen via Umbriel's XDG ScreenCast portal picker (`portal-mirror`)
  # - Rectangular Region via `slurp` + `wl-mirror --region`
  # - Instant Full Screen via `wl-mirror`
  screenMirror = pkgs.writeShellApplication {
    name = "screen-mirror";
    runtimeInputs = [
      config.programs.umbriel.package
      config.programs.noctalia.package
      portalMirror
      pkgs.coreutils
      pkgs.jq
      pkgs.libnotify
      pkgs.procps
      pkgs.slurp
      pkgs.wl-mirror
    ];
    text = ''
      pidfile="''${XDG_RUNTIME_DIR:-/tmp}/screen-mirror.pid"

      is_active() {
        if [ -f "$pidfile" ]; then
          local pid
          pid="$(cat "$pidfile" 2>/dev/null || true)"
          if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
          fi
        fi
        pgrep -x wl-mirror >/dev/null 2>&1 || pgrep -f 'portal-mirror\.py' >/dev/null 2>&1
      }

      stop_active() {
        local stopped=0
        if [ -f "$pidfile" ]; then
          local pid
          pid="$(cat "$pidfile" 2>/dev/null || true)"
          if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
            stopped=1
          fi
          rm -f "$pidfile"
        fi
        if pkill -x wl-mirror 2>/dev/null; then
          stopped=1
        fi
        if pkill -f 'portal-mirror\.py' 2>/dev/null; then
          stopped=1
        fi
        [ "$stopped" -eq 1 ]
      }

      mode="menu"
      arg_dest=""
      arg_src=""

      case "''${1:-}" in
        stop | off | --stop)
          if stop_active; then
            notify-send -a "Screen Mirror" "Screen Mirror" "Stopped mirroring"
          fi
          exit 0
          ;;
        portal | --portal)
          mode="portal"
          arg_dest="''${2:-}"
          ;;
        window | --window)
          mode="window"
          arg_dest="''${2:-}"
          ;;
        region | --region)
          mode="region"
          arg_dest="''${2:-}"
          ;;
        fullscreen | full | --fullscreen)
          mode="fullscreen"
          arg_dest="''${2:-}"
          arg_src="''${3:-}"
          ;;
        menu | --menu | --pick | pick)
          mode="menu"
          arg_dest="''${2:-}"
          ;;
        -h | --help)
          printf 'Usage: screen-mirror [portal | window | region | fullscreen | stop | <dest> [src]]\n'
          exit 0
          ;;
        "")
          mode="toggle"
          ;;
        *)
          mode="fullscreen"
          arg_dest="$1"
          arg_src="''${2:-}"
          ;;
      esac

      if is_active; then
        stop_active || true
        if [ "$mode" = "toggle" ]; then
          notify-send -a "Screen Mirror" "Screen Mirror" "Stopped mirroring"
          exit 0
        fi
        sleep 0.15
      fi

      outputs_json="$(umbriel outputs --json)"
      count="$(printf '%s' "$outputs_json" | jq '[.[] | select(.enabled == true)] | length')"

      if [ "$count" -lt 2 ]; then
        notify-send -u critical -a "Screen Mirror" "Screen Mirror" "Connect a second display (e.g. HDMI) first"
        exit 1
      fi

      pick_output() {
        local prompt="$1"
        local filter_out="''${2:-}"
        local choice
        choice="$(
          printf '%s' "$outputs_json" \
            | jq -r --arg skip "$filter_out" '
                [ .[] | select(.enabled == true and .name != $skip) ]
                | sort_by((.name | startswith("eDP-")), (.focused == true), .name)
                | .[]
                | if (.description // "") != "" and .description != .name
                  then "\(.name) — \(.description)"
                  else .name
                  end
              ' \
            | noctalia dmenu -p "$prompt"
        )" || return 1
        [ -n "$choice" ] || return 1
        printf '%s' "''${choice%% — *}"
      }

      if [ -n "$arg_dest" ]; then
        dest="$arg_dest"
      else
        dest="$(pick_output "Mirror destination")" || exit 0
      fi

      if ! printf '%s' "$outputs_json" | jq -e --arg d "$dest" '
        any(.[] | select(.enabled == true); .name == $d)
      ' >/dev/null; then
        notify-send -u critical -a "Screen Mirror" "Screen Mirror" "Output '$dest' is not active"
        exit 1
      fi

      if [ "$mode" = "toggle" ] || [ "$mode" = "menu" ]; then
        selection="$(
          printf '%s\n' \
            "Portal Picker (Screen or Window)" \
            "Rectangular Region" \
            | noctalia dmenu -p "Mirror to $dest"
        )" || exit 0
        case "$selection" in
          "Portal Picker"*) mode="portal" ;;
          "Rectangular Region"*) mode="region" ;;
          *) exit 0 ;;
        esac
      fi

      run_wl_mirror() {
        local label="$1"
        shift
        local wl_args=("$@")
        (
          my_pid="$BASHPID"
          printf '%s\n' "$my_pid" >"$pidfile"
          tmpdir="$(mktemp -d)"
          fifo="$tmpdir/events"
          mkfifo "$fifo"
          mirror_pid=""
          sub_pid=""
          reader_pid=""
          # shellcheck disable=SC2329
          cleanup() {
            [ -n "$sub_pid" ] && kill -TERM "$sub_pid" 2>/dev/null || true
            [ -n "$reader_pid" ] && kill -TERM "$reader_pid" 2>/dev/null || true
            [ -n "$mirror_pid" ] && kill -TERM "$mirror_pid" 2>/dev/null || true
            if [ -f "$pidfile" ] && [ "$(cat "$pidfile" 2>/dev/null || true)" = "$my_pid" ]; then
              rm -f "$pidfile"
            fi
            rm -rf "$tmpdir"
          }
          trap cleanup EXIT INT TERM HUP

          wl-mirror --fullscreen --scaling fit --title "wl-mirror:$dest" "''${wl_args[@]}" &
          mirror_pid=$!

          umbriel subscribe outputs >"$fifo" &
          sub_pid=$!

          (
            while IFS= read -r _; do
              if ! umbriel outputs --json | jq -e --arg d "$dest" '
                any(.[] | select(.enabled == true); .name == $d)
              ' >/dev/null 2>&1; then
                kill -TERM "$mirror_pid" 2>/dev/null || true
                break
              fi
            done <"$fifo"
          ) &
          reader_pid=$!

          wait "$mirror_pid" || true
        ) >/dev/null 2>&1 </dev/null &
        disown

        sleep 0.15
        if pgrep -x wl-mirror >/dev/null 2>&1; then
          notify-send -a "Screen Mirror" "Screen Mirror" "$label"
        else
          notify-send -u critical -a "Screen Mirror" "Screen Mirror" "wl-mirror failed to start"
          exit 1
        fi
      }

      case "$mode" in
        portal)
          portal-mirror "$dest" 3 >/dev/null 2>&1 </dev/null &
          disown
          ;;
        window)
          portal-mirror "$dest" 2 >/dev/null 2>&1 </dev/null &
          disown
          ;;
        region)
          region="$(slurp)" || exit 0
          [ -n "$region" ] || exit 0
          run_wl_mirror "Mirroring region ($region) → $dest" --region "$region"
          ;;
        fullscreen)
          if [ -n "$arg_src" ]; then
            src="$arg_src"
          else
            src="$(
              printf '%s' "$outputs_json" | jq -r --arg d "$dest" '
                ([.[] | select(.enabled == true and .name != $d)]) as $cand
                | ($cand | map(select(.name | startswith("eDP-"))) | first)
                  // ($cand | map(select(.focused == true)) | first)
                  // ($cand | first)
                  | .name // empty
              '
            )"
          fi
          if [ -z "$src" ] || [ "$src" = "$dest" ]; then
            notify-send -u critical -a "Screen Mirror" "Screen Mirror" "Invalid source/destination outputs"
            exit 1
          fi
          run_wl_mirror "Mirroring $src → $dest" "$src"
          ;;
      esac
    '';
  };

  # Layout-aware Mod+Wheel helper: scrolls across windows/columns when the
  # focused workspace uses `scrolling`, and switches workspaces otherwise.
  umbrielWheelScroll = pkgs.writeShellScriptBin "scroll" ''
    case "$("${umbrielBin}" workspaces)"$'\n' in
      *" [scrolling] (focused)"$'\n'*)
        case "$1" in
          previous) exec "${umbrielBin}" msg window-focus-left ;;
          *) exec "${umbrielBin}" msg window-focus-right ;;
        esac
        ;;
      *)
        case "$1" in
          previous) exec "${umbrielBin}" msg workspace-previous ;;
          *) exec "${umbrielBin}" msg workspace-next ;;
        esac
        ;;
    esac
  '';
in
{
  imports = [
    inputs.noctalia.homeModules.default
    inputs.umbriel.homeModules.default
  ];

  # Runtime deps for Noctalia's theming hooks:
  # - adw-gtk3: the GTK theme the template's apply.sh looks up and syncs
  #   (adw-gtk3 / adw-gtk3-dark depending on light/dark mode)
  # - glib: provides `gsettings`, used by the GTK apply hook to set
  #   org.gnome.desktop.interface gtk-theme / color-scheme
  home.packages = with pkgs; [
    adw-gtk3
    glib
    kdePackages.qt6ct
    screenMirror
  ];

  # GTK theming: use adw-gtk3-dark (matches theme.mode = "dark") so Noctalia's
  # generated CSS applies on top, and give the shell an icon theme (Noctalia
  # resolves app icons through GTK's icon-theme support).
  gtk = {
    enable = true;
    theme.name = "adw-gtk3-dark";
    iconTheme = {
      name = "breeze";
      package = pkgs.kdePackages.breeze-icons;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "kde"; # Uses native KDE theming/KColorScheme
  };

  # Home Manager's qt module writes systemd.user.sessionVariables.QT_PLUGIN_PATH
  # to ~/.config/environment.d/10-home-manager.conf with only the HM user
  # profile, overriding NixOS's profileRelativeSessionVariables in the systemd
  # user manager. Include /run/current-system/sw so Dolphin discovers
  # system-wide KF6 plugins (Ark's extract/compress/DnD plugins, kio-extras,
  # thumbnailers, Breeze, etc.).
  systemd.user.sessionVariables =
    let
      qtVersions = [
        pkgs.qt5
        pkgs.qt6
      ];
      mkQtPaths =
        attr:
        lib.concatStringsSep ":" (
          lib.concatMap (qt: [
            "${config.home.profileDirectory}/${qt.qtbase.${attr}}"
            "/run/current-system/sw/${qt.qtbase.${attr}}"
          ]) qtVersions
        );
    in
    {
      QT_PLUGIN_PATH = lib.mkForce (mkQtPaths "qtPluginPrefix");
      QML2_IMPORT_PATH = lib.mkForce (mkQtPaths "qtQmlPrefix");
      NIX_XDG_DESKTOP_PORTAL_DIR = "/run/current-system/sw/share/xdg-desktop-portal/portals";
    };

  home.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "kde";
  };

  # Cursor theme: Bibata Modern Ice. HM's pointerCursor module installs the
  # package, links it into ~/.icons & $XDG_DATA_HOME/icons, exports
  # XCURSOR_THEME/XCURSOR_SIZE, and fills gtk.cursorTheme for GTK apps.
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
  };

  home.file = {
    ".fumoctl.jpg".source = ../dotfiles/.fumoctl.jpg;
    "Pictures/Wallpapers".source = ../dotfiles/Wallpapers;
  };

  # --- Noctalia Shell ---
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      shell = {
        avatar_path = "${config.home.homeDirectory}/.fumoctl.jpg";
        show_location = false;
        launch_apps_as_systemd_services = true;
        umbriel_overview_type_to_launch_enabled = true;
        umbriel_overview_close_on_launch_enabled = true;
        umbriel_audio_provider_enabled = true;
        greeter_sync.auto_sync = true;
      };

      location.auto_locate = true;

      weather = {
        enabled = true;
        unit = "metric";
      };

      lockscreen = {
        dnd = true;
        blurred_desktop = false;
        blur_intensity = 0.5;
        tint_intensity = 0.3;
        tint_color = "surface";
      };

      lockscreen_widgets = {
        enabled = true;
        schema_version = 2;
        widget_order = [ "clock" ];
        widget.clock = {
          type = "clock";
          cx = 2560.0;
          cy = 720.0;
          placement_width = 5120.0;
          placement_height = 1440.0;
          box_width = 544.0;
          box_height = 304.0;
        };
      };

      theme = {
        builtin = "Tokyo-Night";
        templates = {
          builtin_ids = [
            "gtk3"
            "gtk4"
            "kcolorscheme"
            "umbriel"
          ];
          enable_community_templates = true;
          community_ids = [ "konsole" ];
        };
      };

      hooks.started = [
        "${lib.getExe config.programs.noctalia.package} msg templates-apply"
        "${lib.getExe config.programs.noctalia.package} msg greeter-sync"
      ];

      wallpaper = {
        enabled = true;
        directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
        automation = {
          enabled = true;
          interval_seconds = 300;
          order = "random";
          recursive = true;
          pause_on_fullscreen = true;
        };
      };

      bar.default = {
        capsule_group = [ ];
        start = [
          "media"
          "audio_visualizer"
          "workspaces"
          "spacer_2"
          "active_window"
        ];
        center = [
          "clock"
          "date"
        ];
        end = [
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "mirror"
          "volume"
          "brightness"
          "battery"
          "control-center"
        ];
        font_family = "JetBrainsMono NF Medium";
        font_weight = 400;
        margin_edge = 5;
        margin_ends = 10;
        padding = 10;
      };

      widget = {
        active_window = {
          capsule = true;
          font_scale = 1.1;
          icon_size = 20;
          max_length = 800;
        };
        audio_visualizer = {
          scale = 1.4;
          width = 60;
        };
        "control-center" = {
          glyph = "brand-zhihu";
          scale = 1.25;
        };
        media = {
          hide_artist = true;
          hide_when_no_media = true;
          max_length = 800;
          min_length = 0;
          scale = 1.1;
        };
        network = {
          scale = 1.1;
          show_label = false;
        };
        spacer_2.type = "spacer";
        volume = {
          glyph = "volume";
          scale = 1.1;
        };
        mirror = {
          type = "custom_button";
          glyph = "screen-share";
          tooltip = "Left: mirror menu / stop · Right: portal picker · Middle: region";
          scale = 1.05;
          actions = {
            left = "exec ${screenMirror}/bin/screen-mirror";
            right = "exec ${screenMirror}/bin/screen-mirror portal";
            middle = "exec ${screenMirror}/bin/screen-mirror region";
          };
        };
        battery.scale = 1.1;
        brightness.scale = 1.1;
        clipboard.scale = 1.1;
        notifications.scale = 1.1;
        tray.scale = 1.1;
        workspaces = {
          font_scale = 1.1;
          hide_when_empty = true;
          scale = 1.3;
        };
        clock.scale = 1.1;
        date.scale = 1.1;
      };
    };
  };

  # --- Umbriel Compositor ---
  # `umbriel.service` (installed by `programs.umbriel.enable` in hosts/desktop-env.nix)
  # exports the Wayland session environment and activates `graphical-session.target`,
  # which starts `noctalia.service` automatically. Do NOT add `"noctalia"` to
  # `general.autostart` or a duplicate shell instance will spawn.
  programs.umbriel = {
    enable = true;
    settings = {
      # Noctalia's built-in `umbriel` template renders dynamic theme colors into
      # `~/.config/umbriel/noctalia.toml`; keeping the entry as `"noctalia.toml"`
      # matches `apply.sh` so it leaves the read-only HM symlink untouched.
      include.optional.files = [ "noctalia.toml" ];

      general = {
        mod_key = "Super";
        xwayland = true;
        show_cheatsheet = false;
        autostart = [
          "discord --start-minimized"
          "steam -silent"
        ];
      };

      environment = {
        QT_QPA_PLATFORMTHEME = "kde";
        XCURSOR_THEME = "Bibata-Modern-Ice";
        XCURSOR_SIZE = "24";
      };

      input = {
        keyboard = {
          layout = "us";
          variant = "altgr-intl";
          options = "lv3:ralt_switch";
          numlock_toggle = true;
        };
        mouse.accel_profile = "flat";
        touchpad = {
          tap = true;
          natural_scroll = true;
        };
        cursor = {
          theme = "Bibata-Modern-Ice";
          size = 24;
        };
        focus = {
          follows_mouse = "sloppy";
          hover_raises = false;
        };
      };

      layout = {
        mode = "dwindle";
        gap = 10;
        extent_presets = [
          0.333
          0.5
          0.667
        ];
        dwindle = {
          preserve_split = true;
          new_toward_cursor = true;
        };
        scrolling.default_extent_fraction = 0.5;
      };

      # Persistent workspaces 1..9 on every output (never pruned or renumbered when empty)
      workspace = map (n: { name = toString n; }) (lib.range 1 9);

      appearance = {
        prefer_no_csd = true;
        border_width = 2;
        corner_radius = 12;
        blur = {
          enabled = true;
          optimized = true;
          passes = 2;
          radius = 4;
        };
        shadow = {
          enabled = true;
          softness = 10;
        };
      };

      animation = {
        enabled = true;
        layers.enabled = false;
      };

      hot_corners.top_left = {
        enabled = true;
        delay_ms = 500;
        action = "overview-open";
      };

      window_rule = [
        { blur = true; }
        {
          match.is_focused = false;
          opacity = 0.88;
        }
        {
          match.is_focused = true;
          opacity = 0.94;
        }
        {
          match.app_id = "^dev\\.noctalia\\.Noctalia$";
          default_floating = true;
          default_floating_size_px = {
            width = 1020;
            height = 900;
          };
        }
        {
          match.app_id = "^dev\\.noctalia\\.UmbrielSharePicker$";
          default_floating = true;
          default_floating_size_px = {
            width = 800;
            height = 600;
          };
        }
        {
          match.title = "^(Picture-in-Picture|Picture in picture)$";
          default_floating = true;
          default_maximize = false;
          default_position = {
            x = 20;
            y = 20;
            anchor = "bottom_right";
          };
        }
        {
          match.title = "^notificationtoasts_.+_desktop";
          default_position = {
            x = 0;
            y = 0;
            anchor = "bottom_right";
          };
          default_focused = false;
          default_pinned = true;
        }
        {
          match.app_id = "^org\\.freedesktop\\.impl\\.portal\\.desktop\\.kde$";
          default_floating = true;
        }
        {
          match.app_id = "^[Ww]indscribe$";
          default_floating = true;
          border_width = 0;
          blur = false;
          shadow = false;
          corner_radius = 0;
          opacity = 1.0;
        }
        # Keep gamescope (whose Wayland backend clears app_id to "") and native
        # Steam/Proton games opaque and unblurred so 5120x1440@200Hz frames are
        # not composited through Kawase blur and can use direct scanout.
        {
          match.app_id = "^(gamescope|steam_app_.*|)$";
          blur = false;
          shadow = false;
          opacity = 1.0;
        }
        # Route `screen-mirror` windows (`wl-mirror` for region/fullscreen and
        # `portal-mirror` `dev.ultix.ScreenMirror.<output>` for XDG ScreenCast)
        # onto the target display fullscreen, unblurred, opaque, and unfocused —
        # Umbriel ignores Wayland's `xdg_toplevel.set_fullscreen` target output.
        {
          match.app_id = "^(at\\.yrlf\\.wl_mirror|dev\\.ultix\\.ScreenMirror\\..+)$";
          default_fullscreen = true;
          default_focused = false;
          focus_on_activate = false;
          blur = false;
          shadow = false;
          opacity = 1.0;
        }
      ]
      ++ lib.concatMap (output: [
        {
          match = {
            app_id = "^at\\.yrlf\\.wl_mirror$";
            title = "^wl-mirror:${output}$";
          };
          default_output = output;
        }
        {
          match.app_id = "^dev\\.ultix\\.ScreenMirror\\.${output}$";
          default_output = output;
        }
      ]) mirrorOutputs;

      layer_rule = [
        {
          match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd|desktop-widget-[^\"]*)$";
          blur = true;
          blur_ignore_alpha = 0.5;
          blur_popups = true;
        }
        {
          match.namespace = "^noctalia-(notification|dock|panel|attached-panel|osd)$";
          blur_optimized = false;
        }
        {
          match.namespace = "^gtk-layer-shell$";
          blur = true;
        }
      ];

      keybinds = {
        # Applications & session
        "Mod+Return" = {
          action = "spawn konsole";
          repeat = false;
        };
        "Mod+E" = {
          action = "spawn dolphin";
          repeat = false;
        };
        "Mod+B" = {
          action = "spawn brave --new-window";
          repeat = false;
        };
        "Mod+Q" = {
          action = "window-close";
          repeat = false;
        };
        "Mod+Shift+Ctrl+K" = {
          action = "window-kill";
          repeat = false;
        };
        "Mod+M" = {
          action = "session-quit";
          repeat = false;
        };
        "Mod+Slash" = {
          action = "cheatsheet-toggle";
          repeat = false;
        };
        "Mod+Shift+Escape" = {
          action = "shortcuts-inhibit-toggle";
          allow_when_inhibited = true;
          repeat = false;
        };

        # Window state & layout
        "Mod+F" = {
          action = "window-toggle-fullscreen";
          repeat = false;
        };
        "Mod+T" = {
          action = "window-toggle-floating";
          repeat = false;
        };
        "Mod+Shift+T" = {
          action = "window-focus-switch-floating";
          repeat = false;
        };
        "Mod+P" = {
          action = "window-toggle-pinned";
          repeat = false;
        };
        "Mod+J" = {
          action = "layout-toggle-split";
          repeat = false;
        };
        "Mod+Shift+Tab" = {
          action = "workspace-set-layout toggle dwindle scrolling";
          repeat = false;
        };
        "Mod+Alt+Tab" = {
          action = "overview-toggle";
          repeat = false;
        };

        # Noctalia Shell IPC controls
        "Mod+Space" = "spawn noctalia msg panel-toggle launcher";
        "Mod+V" = "spawn noctalia msg panel-toggle clipboard";
        "Mod+S" = "spawn noctalia msg panel-toggle control-center";
        "Mod+Comma" = "spawn noctalia msg settings-toggle";
        "Alt+Tab" = "spawn noctalia msg window-switcher hold";
        "Alt+Shift+Tab" = "spawn noctalia msg window-switcher hold reverse";

        # Screenshots & display mirroring
        "Mod+Shift+S" = {
          action = "spawn noctalia msg screenshot-fullscreen";
          repeat = false;
        };
        "Mod+Shift+Ctrl+S" = {
          action = "spawn noctalia msg screenshot-region";
          repeat = false;
        };
        "Mod+Shift+P" = {
          action = "spawn ${screenMirror}/bin/screen-mirror";
          repeat = false;
        };
        "Mod+Shift+Ctrl+P" = {
          action = "spawn ${screenMirror}/bin/screen-mirror region";
          repeat = false;
        };
        "XF86Display" = {
          action = "spawn ${screenMirror}/bin/screen-mirror";
          repeat = false;
        };

        # Focus & directional movement
        "Mod+Left" = "window-focus-left";
        "Mod+Right" = "window-focus-right";
        "Mod+Up" = "window-focus-up";
        "Mod+Down" = "window-focus-down";
        "Mod+Shift+Left" = "window-move-left";
        "Mod+Shift+Right" = "window-move-right";
        "Mod+Shift+Up" = "window-move-up";
        "Mod+Shift+Down" = "window-move-down";

        # Layout-aware scroll: windows in `scrolling`, workspaces otherwise
        "Mod+WheelDown" = "spawn ${umbrielWheelScroll}/bin/scroll next window or workspace";
        "Mod+WheelUp" = "spawn ${umbrielWheelScroll}/bin/scroll previous window or workspace";

        # Media, audio & brightness (routed through Noctalia for OSDs)
        "XF86AudioRaiseVolume" = {
          action = "spawn noctalia msg volume-up";
          allow_when_locked = true;
        };
        "XF86AudioLowerVolume" = {
          action = "spawn noctalia msg volume-down";
          allow_when_locked = true;
        };
        "XF86AudioMute" = {
          action = "spawn noctalia msg volume-mute";
          allow_when_locked = true;
          repeat = false;
        };
        "XF86AudioMicMute" = {
          action = "spawn noctalia msg mic-mute";
          allow_when_locked = true;
          repeat = false;
        };
        "XF86AudioPlay" = {
          action = "spawn noctalia msg media toggle";
          allow_when_locked = true;
          repeat = false;
        };
        "XF86AudioNext" = {
          action = "spawn noctalia msg media next";
          allow_when_locked = true;
        };
        "XF86AudioPrev" = {
          action = "spawn noctalia msg media previous";
          allow_when_locked = true;
        };
        "XF86MonBrightnessUp" = {
          action = "spawn noctalia msg brightness-up";
          allow_when_locked = true;
        };
        "XF86MonBrightnessDown" = {
          action = "spawn noctalia msg brightness-down";
          allow_when_locked = true;
        };
      }
      // lib.mergeAttrsList (
        map (
          n:
          let
            ws = toString n;
          in
          {
            "Mod+${ws}" = "workspace-switch ${ws}";
            "Mod+Shift+${ws}" = "window-move-to-workspace ${ws}";
          }
        ) (lib.range 1 9)
      );
    };
  };
}
