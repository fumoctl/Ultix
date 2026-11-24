{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  # Umbriel-aware gamescope wrapper (`gs-run`).
  # Opens as a tiled/windowed Umbriel client by default (`Mod+F` toggles true
  # native fullscreen); pass `-f` / `--fullscreen` to start fullscreen immediately.
  #
  # Runs a Wine command inside gamescope and waits on `wineserver -w` afterwards
  # so launcher executables (e.g. Bottles's `wine start /wait InitSetting.exe`)
  # that spawn the main game `.exe` and exit immediately do not cause
  # `gamescopereaper` to SIGTERM the spawned game. Also reaps any leftover
  # `ntsync` helper processes (`winedevice.exe`) attached to `gamescopereaper`
  # when the session ends.
  #
  # THE FINALS/Deadlock/CS2/etc (keep game vsync on, mangohud fps limit = a bit below half screen refresh rate 200hz=96limit)
  # gs-run --vrr --force-grab-cursor -- env MANGOHUD_CONFIG="read_cfg,no_display,fps_limit=96,fps_limit_method=early" LSFGVK_PROFILE="default" mangohud %command%
  # add MESA_LOADER_DRIVER_OVERRIDE=zink inside gs-run if your game uses opengl to translate it to vulkan first so lsfg-vk works on it
  # show mangohud with Right Shift + F12
  #
  # for games that "upscale" to fit automatically (they just stretch) like some visual novels do, use --scale to lower the game's detected screen resolution and then use fsr to upscale to lose less quality
  # gs-run --fsr --sharpness 12 --scale 0.75 --16:9 %command%

  gs-wine-wait = pkgs.writeShellApplication {
    name = "gs-wine-wait";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      wineserver_bin="$1"
      shift
      reaper_pid="$PPID"

      # shellcheck disable=SC2329
      cleanup() {
        local child
        local -a children=()
        "$wineserver_bin" -k 2>/dev/null || true
        if [ -r "/proc/$reaper_pid/comm" ] && [ "$(<"/proc/$reaper_pid/comm")" = "gamescopereaper" ]; then
          read -r -a children <"/proc/$reaper_pid/task/$reaper_pid/children" || true
          for child in "''${children[@]}"; do
            if [ "$child" != "$$" ]; then
              kill -9 "$child" 2>/dev/null || true
            fi
          done
        fi
      }
      trap cleanup EXIT
      trap 'exit 143' INT TERM HUP

      rc=0
      "$@" || rc=$?
      "$wineserver_bin" -w || true
      exit "$rc"
    '';
  };

  gs-run = pkgs.writeShellApplication {
    name = "gs-run";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      usage() {
        cat <<'EOF'
      Usage: gs-run [options] [--] <command...>

      Auto-detects the focused Umbriel monitor's native resolution, refresh rate,
      HDR, and VRR state, then launches the game inside gamescope.

      Options:
        --16:9               Render at 16:9 inside native height (e.g. 2560x1440 on 32:9)
        --21:9               Render at 21:9 inside native height (e.g. 3440x1440 on 32:9)
        --4:3                Render at 4:3 inside native height (e.g. 1920x1440)
        --scale <factor>     Internal render scale (0.1–1.0, e.g. 0.75) upscaled to native
        --fsr                Shorthand for -F fsr (AMD FSR 1.0 upscaling)
        -F, --filter <name>  Upscaler filter: linear (default), fsr, nis, nearest, pixel
        --sharpness <0-20>   Upscaler sharpness (0 = max, 20 = min)
        -f, --fullscreen     Start fullscreen immediately (default: windowed/tiled; Mod+F toggles)
        -b, --borderless     Start as a full-monitor borderless window
        -g, --grab           Grab keyboard
        --force-grab-cursor  Always lock relative mouse cursor inside gamescope
        --mangoapp           Enable MangoHud's mangoapp inside gamescope
        --backend <name>     Gamescope backend override (wayland, sdl, auto)
        --hdr                Force --hdr-enabled
        --vrr                Force --adaptive-sync
        --dry-run            Print the resolved gamescope command without running it
        -h, --help           Show this help

      Examples:
        Visual novels (16:9 / 4:3):
          gs-run --16:9 %command%
          gs-run --4:3 %command%
        2D pixel-art / hand-drawn:
          gs-run --16:9 -F pixel %command%
          gs-run --16:9 %command%
        3D native / upscaled:
          gs-run -f %command%
          gs-run -f --fsr --scale 0.75 %command%
        Frame generation (lsfg-vk) + MangoHud:
          gs-run --mangoapp env LSFGVK_PROFILE="default" %command%
      EOF
      }

      if [ $# -eq 0 ]; then
        usage
        exit 0
      fi

      # Save and clear Steam's LD_PRELOAD and ancient Ubuntu 12 steam-runtime
      # LD_LIBRARY_PATH immediately so Nix helper binaries (umbriel, jq, gawk)
      # and gamescope itself use their Nix store RPATHs cleanly, then restore
      # both for the game command inside gamescope.
      saved_preload="''${LD_PRELOAD:-}"
      saved_ld_library_path="''${LD_LIBRARY_PATH:-}"
      saved_disable_lsfgvk="''${DISABLE_LSFGVK:-}"
      unset LD_PRELOAD
      if [ -n "''${SYSTEM_LD_LIBRARY_PATH:-}" ]; then
        export LD_LIBRARY_PATH="$SYSTEM_LD_LIBRARY_PATH"
      else
        unset LD_LIBRARY_PATH
      fi

      aspect=""
      scale="1.0"
      filter="linear"
      window_mode=""
      backend=""
      dry_run=0
      force_hdr=0
      force_vrr=0
      extra_gs=()

      while [ $# -gt 0 ]; do
        case "$1" in
          -h | --help)
            usage
            exit 0
            ;;
          --16:9)
            aspect="16:9"
            shift
            ;;
          --21:9)
            aspect="21:9"
            shift
            ;;
          --4:3)
            aspect="4:3"
            shift
            ;;
          --scale)
            scale="''${2:?--scale requires a factor (e.g. 0.75)}"
            shift 2
            ;;
          --fsr)
            filter="fsr"
            shift
            ;;
          -F | --filter)
            filter="''${2:?--filter requires a name}"
            shift 2
            ;;
          --sharpness | --fsr-sharpness)
            extra_gs+=("--sharpness" "''${2:?--sharpness requires 0-20}")
            shift 2
            ;;
          -f | --fullscreen)
            window_mode="-f"
            shift
            ;;
          -b | --borderless)
            window_mode="-b"
            shift
            ;;
          -g | --grab)
            extra_gs+=("-g")
            shift
            ;;
          --force-grab-cursor)
            extra_gs+=("--force-grab-cursor")
            shift
            ;;
          --mangoapp)
            extra_gs+=("--mangoapp")
            shift
            ;;
          --backend)
            backend="''${2:?--backend requires sdl, wayland, or auto}"
            shift 2
            ;;
          --hdr)
            force_hdr=1
            shift
            ;;
          --vrr)
            force_vrr=1
            shift
            ;;
          --dry-run)
            dry_run=1
            shift
            ;;
          --)
            shift
            break
            ;;
          -*)
            extra_gs+=("$1")
            shift
            ;;
          *)
            break
            ;;
        esac
      done

      if [ $# -eq 0 ] && [ "$dry_run" -eq 0 ]; then
        echo "gs-run: missing command to execute" >&2
        exit 2
      fi

      out_w=1920
      out_h=1080
      out_hz=60
      out_hdr="false"
      out_vrr="false"

      if detected="$(
        ${lib.getExe config.programs.umbriel.package} outputs --json 2>/dev/null \
          | ${lib.getExe pkgs.jq} -r '
              (map(select(.enabled and .focused))[0] // map(select(.enabled))[0]) as $o
              | select($o != null)
              | ($o.modes | map(select(.current))[0] // $o.modes[0]) as $m
              | (($o.transform // "normal") | IN("90", "270", "flipped-90", "flipped-270")) as $rot
              | ($m.width // $o.logical_size.width // 1920) as $rw
              | ($m.height // $o.logical_size.height // 1080) as $rh
              | (if $rot then $rh else $rw end) as $w
              | (if $rot then $rw else $rh end) as $h
              | ((($m.refresh_mhz // 60000) + 500) / 1000 | floor) as $hz
              | "\($w) \($h) \($hz) \($o.hdr_active // false) \($o.adaptive_sync // false)"
            '
      )" && [ -n "$detected" ]; then
        read -r out_w out_h out_hz out_hdr out_vrr <<<"$detected"
      fi

      base_w="$out_w"
      base_h="$out_h"
      case "$aspect" in
        16:9)
          base_w=$(( ((out_h * 16 / 9) + 1) / 2 * 2 ))
          ;;
        21:9)
          if [ "$out_h" -eq 1440 ]; then
            base_w=3440
          elif [ "$out_h" -eq 1080 ]; then
            base_w=2560
          else
            base_w=$(( ((out_h * 21 / 9) + 1) / 2 * 2 ))
          fi
          ;;
        4:3)
          base_w=$(( ((out_h * 4 / 3) + 1) / 2 * 2 ))
          ;;
      esac

      read -r game_w game_h <<<"$(
        ${lib.getExe pkgs.gawk} -v w="$base_w" -v h="$base_h" -v s="$scale" '
          BEGIN {
            if (s <= 0) s = 1.0
            gw = int((w * s + 1) / 2) * 2
            gh = int((h * s + 1) / 2) * 2
            if (gw < 2) gw = 2
            if (gh < 2) gh = 2
            printf "%d %d\n", gw, gh
          }
        '
      )"

      gamescope_bin="gamescope"
      if ! command -v "$gamescope_bin" >/dev/null 2>&1; then
        gamescope_bin="${lib.getExe config.programs.gamescope.package}"
      fi

      # In windowed mode, size the initial outer window to the target aspect
      # (Umbriel dynamically resizes -W/-H when tiled or Mod+F fullscreened);
      # in fullscreen/borderless mode, target the full monitor directly.
      win_w="$base_w"
      win_h="$base_h"
      if [ -n "$window_mode" ]; then
        win_w="$out_w"
        win_h="$out_h"
      fi

      use_hdr=0
      if [ "$force_hdr" -eq 1 ] || [ "$out_hdr" = "true" ]; then
        use_hdr=1
      fi

      gs_cmd=(
        "$gamescope_bin"
        -W "$win_w"
        -H "$win_h"
        -w "$game_w"
        -h "$game_h"
        -r "$out_hz"
        -F "$filter"
      )

      if [ -n "$backend" ]; then
        gs_cmd+=("--backend" "$backend")
      fi

      if [ -n "$window_mode" ]; then
        gs_cmd+=("$window_mode")
      fi
      if [ "$use_hdr" -eq 1 ]; then
        gs_cmd+=("--hdr-enabled")
      fi
      if [ "$force_vrr" -eq 1 ] || [ "$out_vrr" = "true" ]; then
        gs_cmd+=("--adaptive-sync")
      fi
      if [ "''${#extra_gs[@]}" -gt 0 ]; then
        gs_cmd+=("''${extra_gs[@]}")
      fi

      inner_env=("DISABLE_LSFGVK=$saved_disable_lsfgvk")
      if [ -n "$saved_preload" ]; then
        inner_env+=("LD_PRELOAD=$saved_preload")
      fi
      if [ -n "$saved_ld_library_path" ]; then
        inner_env+=("LD_LIBRARY_PATH=$saved_ld_library_path")
      fi

      while [ $# -gt 0 ]; do
        case "$1" in
          env)
            if [ $# -gt 1 ] && [[ "$2" != -* ]]; then
              shift
            else
              break
            fi
            ;;
          [A-Za-z_]*=*)
            if [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
              inner_env+=("$1")
              shift
            else
              break
            fi
            ;;
          *)
            break
            ;;
        esac
      done

      wineserver_bin=""
      wineprefix_arg=""
      for arg in "$@"; do
        case "$arg" in
          WINEPREFIX=*)
            wineprefix_arg="$arg"
            ;;
          */wine | */wine64)
            if [ -z "$wineserver_bin" ] && [ -x "''${arg%/*}/wineserver" ]; then
              wineserver_bin="''${arg%/*}/wineserver"
            fi
            ;;
          wine | wine64)
            if [ -z "$wineserver_bin" ]; then
              wineserver_bin="$(command -v wineserver 2>/dev/null || true)"
            fi
            ;;
        esac
      done

      if [ -n "$wineserver_bin" ] && [ -n "$wineprefix_arg" ]; then
        inner_env+=("$wineprefix_arg")
      fi

      inner_cmd=(env)
      if [ -z "$saved_disable_lsfgvk" ]; then
        inner_cmd+=(-u DISABLE_LSFGVK)
        inner_env=("''${inner_env[@]:1}")
      fi
      if [ "''${#inner_env[@]}" -gt 0 ]; then
        inner_cmd+=("''${inner_env[@]}")
      fi
      if [ -n "$wineserver_bin" ]; then
        inner_cmd+=("${lib.getExe gs-wine-wait}" "$wineserver_bin")
      fi
      inner_cmd+=("$@")

      full_cmd=("''${gs_cmd[@]}" -- "''${inner_cmd[@]}")

      if [ "$dry_run" -eq 1 ]; then
        printf '%q ' "''${full_cmd[@]}"
        printf '\n'
        exit 0
      fi

      export DISABLE_LSFGVK=1
      exec "''${full_cmd[@]}"
    '';
  };

  proton-ge-9-12 = pkgs.stdenvNoCC.mkDerivation {
    pname = "proton-ge-bin";
    version = "GE-Proton9-12";
    src = pkgs.fetchurl {
      url = "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-12/GE-Proton9-12.tar.gz";
      hash = "sha512-P1NkfBg7ieWE/EmI29OXmAfnDxXnAI0rZDqBNTzaIQJgELxJ4+scdoTYgA8P5rlQhfluIOzUhbhefFZFZMLdCQ==";
    };
    buildCommand = ''
      mkdir -p "$out"
      tar -C "$out" --strip=1 -x -f "$src"
    '';
  };

  lsfgVkConf =
    let
      unvalidated = (pkgs.formats.toml { }).generate "lsfg-vk-conf.toml" {
        version = 2;
        global = {
          allow_fp16 = true;
          log_level = "info";
        };
        profile = [
          {
            name = "default";
            multiplier = 2;
            flow_scale = 0.85;
            performance_mode = false;
            color_space = "srgb";
            transfer_function = "srgb";
            pacing_mode = "vsync";
            override_present_mode = false;
            preserve_swapchain_image_count = false;
          }
          {
            name = "vsync";
            multiplier = 2;
            flow_scale = 0.85;
            performance_mode = false;
            color_space = "srgb";
            transfer_function = "srgb";
            pacing_mode = "vsync";
            override_present_mode = true;
            preserve_swapchain_image_count = false;
          }
          {
            name = "performance";
            multiplier = 2;
            flow_scale = 0.75;
            performance_mode = true;
            color_space = "srgb";
            transfer_function = "srgb";
            pacing_mode = "vsync";
            override_present_mode = false;
            preserve_swapchain_image_count = false;
          }
          {
            name = "performance-vsync";
            multiplier = 2;
            flow_scale = 0.75;
            performance_mode = true;
            color_space = "srgb";
            transfer_function = "srgb";
            pacing_mode = "vsync";
            override_present_mode = true;
            preserve_swapchain_image_count = false;
          }
          {
            name = "hdr";
            multiplier = 2;
            flow_scale = 0.85;
            performance_mode = false;
            color_space = "hdr10";
            transfer_function = "pq";
            pacing_mode = "vsync";
            override_present_mode = false;
            preserve_swapchain_image_count = false;
          }
          {
            name = "hdr-vsync";
            multiplier = 2;
            flow_scale = 0.85;
            performance_mode = false;
            color_space = "hdr10";
            transfer_function = "pq";
            pacing_mode = "vsync";
            override_present_mode = true;
            preserve_swapchain_image_count = false;
          }
        ];
      };
    in
    pkgs.runCommandLocal "lsfg-vk-conf.toml" { } ''
      ${pkgs.lsfg-vk}/bin/lsfg-vk-cli validate -c "${unvalidated}" >/dev/null
      cp "${unvalidated}" "$out"
    '';

  # Run `winetricks` (GUI or CLI verbs) against a regular non-UMU Bottle inside
  # a multi-arch Wine FHS environment matching `unstable.bottles` (full 32/64-bit
  # FreeType/GStreamer/Vulkan/X11/Wayland libs, and no `--tmpfs /tmp` so
  # `/tmp/.wine-$UID` `wineserver` sockets are shared cleanly with Bottles).
  bottles-winetricks-inner = pkgs.writeShellApplication {
    name = "bottles-winetricks-inner";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
    ];
    text = ''
      usage() {
        cat <<'EOF'
      Usage:
        bottles-winetricks <bottle-name-or-path> [winetricks-args-or-verbs...]
        bottles-winetricks --list

      Examples:
        bottles-winetricks Soda                  # Open Winetricks GUI for bottle 'Soda'
        bottles-winetricks Soda cjkfonts wmp11   # Install verbs into bottle 'Soda'
      EOF
      }

      bottles_root="''${XDG_DATA_HOME:-$HOME/.local/share}/bottles"
      bottles_dir="$bottles_root/bottles"

      yaml_field() {
        local val
        val="$(sed -n "/^$1:/{s/^$1:[[:space:]]*//;s/[[:space:]]*$//;p;q;}" "$2")"
        if [[ "''${#val}" -ge 2 && ( "$val" == \"*\" || "$val" == \'*\' ) ]]; then
          val="''${val:1:-1}"
        fi
        printf '%s\n' "$val"
      }

      list_bottles() {
        shopt -s nullglob
        local found=0
        for yml in "$bottles_dir"/*/bottle.yml; do
          local dir name runner
          dir="$(dirname "$yml")"
          name="$(yaml_field Name "$yml")"
          runner="$(yaml_field Runner "$yml")"
          printf '  %s (dir: %s, runner: %s)\n' "''${name:-$(basename "$dir")}" "$(basename "$dir")" "''${runner:-unknown}"
          found=1
        done
        if [[ "$found" -eq 0 ]]; then
          printf '  (no regular bottles found in %s)\n' "$bottles_dir"
        fi
      }

      if [[ $# -eq 0 ]]; then
        usage >&2
        printf '\nAvailable bottles:\n' >&2
        list_bottles >&2
        exit 1
      fi

      case "$1" in
        -h | --help)
          usage
          printf '\nAvailable bottles:\n'
          list_bottles
          exit 0
          ;;
        -l | --list)
          list_bottles
          exit 0
          ;;
      esac

      target="$1"
      shift

      bottle_path=""
      if [[ -f "$target/bottle.yml" ]]; then
        bottle_path="$(realpath "$target")"
      elif [[ -f "$bottles_dir/$target/bottle.yml" ]]; then
        bottle_path="$bottles_dir/$target"
      else
        shopt -s nullglob
        for yml in "$bottles_dir"/*/bottle.yml; do
          name="$(yaml_field Name "$yml")"
          if [[ "$name" == "$target" ]]; then
            bottle_path="$(dirname "$yml")"
            break
          fi
        done
      fi

      if [[ -z "$bottle_path" ]]; then
        printf 'bottles-winetricks: bottle not found: %s\n\nAvailable bottles:\n' "$target" >&2
        list_bottles >&2
        exit 1
      fi

      yml="$bottle_path/bottle.yml"
      runner="$(yaml_field Runner "$yml")"
      runner_path="$(yaml_field RunnerPath "$yml")"

      resolved_runner=""
      for candidate in \
        "$runner_path" \
        "$bottles_root/runners/$runner" \
        "''${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d/$runner"; do
        if [[ -n "$candidate" && -d "$candidate" ]]; then
          resolved_runner="$candidate"
          break
        fi
      done

      if [[ -z "$resolved_runner" ]]; then
        printf 'bottles-winetricks: runner "%s" for bottle "%s" was not found\n' "$runner" "$target" >&2
        exit 1
      fi

      wine_bin_dir=""
      for bin_candidate in \
        "$resolved_runner/bin" \
        "$resolved_runner/files/bin" \
        "$resolved_runner/dist/bin"; do
        if [[ -x "$bin_candidate/wine" ]]; then
          wine_bin_dir="$bin_candidate"
          break
        fi
      done

      if [[ -z "$wine_bin_dir" ]]; then
        printf 'bottles-winetricks: no executable wine binary found in %s\n' "$resolved_runner" >&2
        exit 1
      fi

      wine_root="$(dirname "$wine_bin_dir")"

      ld_paths=()
      for lib_dir in \
        "$wine_root/lib64" \
        "$wine_root/lib" \
        "$wine_root/lib32" \
        "$wine_root/lib64/wine/x86_64-unix" \
        "$wine_root/lib/wine/x86_64-unix" \
        "$wine_root/lib/wine/i386-unix" \
        "$wine_root/lib32/wine/i386-unix"; do
        if [[ -d "$lib_dir" ]]; then
          ld_paths+=("$lib_dir")
        fi
      done
      joined_ld=""
      if [[ "''${#ld_paths[@]}" -gt 0 ]]; then
        joined_ld="$(IFS=:; printf '%s' "''${ld_paths[*]}")"
      fi

      dll_paths=()
      for dll_dir in \
        "$wine_root/lib64/wine" \
        "$wine_root/lib/wine" \
        "$wine_root/lib32/wine"; do
        if [[ -d "$dll_dir" ]]; then
          dll_paths+=("$dll_dir")
        fi
      done
      joined_dll=""
      if [[ "''${#dll_paths[@]}" -gt 0 ]]; then
        joined_dll="$(IFS=:; printf '%s' "''${dll_paths[*]}")"
      fi

      gst_paths=()
      for gst_dir in \
        "$wine_root/lib64/gstreamer-1.0" \
        "$wine_root/lib/gstreamer-1.0" \
        "$wine_root/lib32/gstreamer-1.0"; do
        if [[ -d "$gst_dir" ]]; then
          gst_paths+=("$gst_dir")
        fi
      done
      joined_gst=""
      if [[ "''${#gst_paths[@]}" -gt 0 ]]; then
        joined_gst="$(IFS=:; printf '%s' "''${gst_paths[*]}")"
      fi

      # When a regular Bottle uses a Proton runner directly (without `./proton`),
      # Proton's `wined3d.dll` links against `libvkd3d-1.dll` and `libvkd3d-shader-1.dll`
      # from `<runner>/files/lib{64,}/vkd3d/`, which `./proton` normally copies into
      # `system32`/`syswow64`. Seed them if missing so D3D9/DirectShow registrations
      # (such as `lavfilters`'s `LAVVideo.ax`) succeed instead of failing `regsvr32` (0x3).
      shopt -s nullglob
      if [[ -d "$wine_root/lib64/vkd3d" && -d "$bottle_path/drive_c/windows/system32" ]]; then
        for dll in "$wine_root/lib64/vkd3d"/*.dll; do
          dest_dll="$bottle_path/drive_c/windows/system32/$(basename "$dll")"
          if [[ ! -e "$dest_dll" ]]; then
            install -m 0644 "$dll" "$dest_dll"
          fi
        done
      fi
      if [[ -d "$wine_root/lib/vkd3d" && -d "$bottle_path/drive_c/windows/syswow64" ]]; then
        for dll in "$wine_root/lib/vkd3d"/*.dll; do
          dest_dll="$bottle_path/drive_c/windows/syswow64/$(basename "$dll")"
          if [[ ! -e "$dest_dll" ]]; then
            install -m 0644 "$dll" "$dest_dll"
          fi
        done
      fi

      # Scope runner `LD_LIBRARY_PATH` / `WINEDLLPATH` / `GST_PLUGIN_SYSTEM_PATH_1_0`
      # strictly to `wine`/`wine64`/`wineserver` shims rather than exporting them globally:
      # Proton ships older `libgraphene`/`libgst*` in `<runner>/files/lib64`, which would
      # otherwise hijack GTK4 `zenity` (`libEGL.so.1` missing) when Winetricks opens its GUI.
      wrapper_dir="$(mktemp -d -t bottles-winetricks.XXXXXX)"
      trap 'rm -rf "$wrapper_dir"' EXIT

      export _BW_LD_PATHS="$joined_ld"
      export _BW_DLL_PATHS="$joined_dll"
      export _BW_GST_PATHS="$joined_gst"
      export _BW_WINELOADER="$wine_bin_dir/wine"

      write_wine_shim() {
        local shim_name="$1"
        local real_bin="$2"
        {
          cat <<'EOF'
      #!${pkgs.runtimeShell}
      if [[ -n "''${_BW_LD_PATHS:-}" ]]; then
        export LD_LIBRARY_PATH="''${_BW_LD_PATHS}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      fi
      if [[ -n "''${_BW_DLL_PATHS:-}" ]]; then
        export WINEDLLPATH="''${_BW_DLL_PATHS}''${WINEDLLPATH:+:$WINEDLLPATH}"
      fi
      if [[ -n "''${_BW_GST_PATHS:-}" ]]; then
        export GST_PLUGIN_SYSTEM_PATH_1_0="''${_BW_GST_PATHS}"
      fi
      export WINELOADER="''${_BW_WINELOADER}"
      EOF
          printf 'exec %q "$@"\n' "$real_bin"
        } > "$wrapper_dir/$shim_name"
        chmod +x "$wrapper_dir/$shim_name"
      }

      write_wine_shim "wine" "$wine_bin_dir/wine"
      export WINE="$wrapper_dir/wine"
      export WINE_BIN="$wine_bin_dir/wine"

      if [[ -x "$wine_bin_dir/wine64" ]]; then
        write_wine_shim "wine64" "$wine_bin_dir/wine64"
        export WINE64="$wrapper_dir/wine64"
      fi

      if [[ -x "$wine_bin_dir/wineserver" ]]; then
        write_wine_shim "wineserver" "$wine_bin_dir/wineserver"
        export WINESERVER="$wrapper_dir/wineserver"
        export WINESERVER_BIN="$wine_bin_dir/wineserver"
      fi

      export WINEPREFIX="$bottle_path"
      export WINEDLLOVERRIDES="winemenubuilder.exe=d''${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
      export WINETRICKS_LATEST_VERSION_CHECK="disabled"
      export PATH="$wrapper_dir:$wine_bin_dir:$PATH"

      printf 'bottles-winetricks: prefix=%s\nbottles-winetricks: wine=%s\n' "$WINEPREFIX" "$WINE_BIN" >&2
      winetricks "$@"
    '';
  };

  bottles-winetricks = pkgs.unstable.buildFHSEnv {
    name = "bottles-winetricks";
    multiArch = true;
    targetPkgs = _: [
      bottles-winetricks-inner
      pkgs.winetricks
    ];
    multiPkgs =
      p:
      with p;
      [
        alsa-lib
        alsa-plugins
        attr
        cups
        dbus
        dosbox
        fontconfig
        freetype
        giflib
        glib
        glibc
        gnutls
        gsm
        gtk3
        libgcrypt
        libglvnd
        libgpg-error
        libgphoto2
        libjpeg_turbo
        libkrb5
        libpcap
        libpng
        libpthread-stubs
        libpulseaudio
        libsm
        libtiff
        libunwind
        libusb1
        libv4l
        libva
        libx11
        libxaw
        libxcb
        libxcomposite
        libxcursor
        libxdmcp
        libxext
        libxfixes
        libxi
        libxinerama
        libxkbcommon
        libxml2
        libxmu
        libxrandr
        libxrender
        libxslt
        libxv
        libxxf86vm
        mpg123
        ncurses
        ocl-icd
        openal
        openldap
        p11-kit
        samba4
        sane-backends
        SDL2
        udev
        vulkan-loader
        wayland
        zlib
      ]
      ++ (with p.gst_all_1; [
        gstreamer
        gst-plugins-base
        gst-plugins-good
        gst-plugins-ugly
        gst-plugins-bad
        gst-libav
      ]);
    runScript = "bottles-winetricks-inner";
    passthru.inner = bottles-winetricks-inner;
  };
in
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.steam-hardware.enable = true;

  programs.gamemode.enable = true;
  programs.gamescope.enable = true;

  programs.steam = {
    enable = true;
    extest.enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
  };

  home-manager.users.fumoctl = {
    # Declarative `lsfg-vk` configuration (`default`, `vsync`, `performance`,
    # `performance-vsync`, `hdr`, and `hdr-vsync` profiles),
    # validated at build time via `lsfg-vk-cli validate`.
    xdg.configFile."lsfg-vk/conf.toml" = {
      source = lsfgVkConf;
      force = true;
    };

    # Materialize Nix-managed Proton builds into `~/.local/share/Steam/compatibilitytools.d`
    # as real directories containing symlinks into `/nix/store`:
    # - Steam, Bottles, `umu-run`, and `bottles-winetricks` all scan this path natively
    #   with zero Bottles source patches, and
    # - keeping each outer tool directory a real directory ensures `Path.resolve()` in
    #   UMU `game.yml` records the stable `~/.local/share/Steam/compatibilitytools.d/<name>`
    #   path rather than a transient `/nix/store/<hash>` path that GC could remove.
    home.activation.syncSteamCompatTools =
      inputs.home-manager.lib.hm.dag.entryAfter [ "writeBoundary" ]
        ''
          compat_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/Steam/compatibilitytools.d"
          mkdir -p "$compat_dir"
          # `makeSteamCompatTool` packages put a warning file in `out` and the actual
          # runner directory in `steamcompattool`.
          pairs=(
            "Proton-CachyOS:${pkgs.proton-cachyos-bin_edge.steamcompattool}"
            "Proton-GE:${pkgs.proton-ge-bin_edge.steamcompattool}"
            "GE-Proton9-12:${proton-ge-9-12}"
          )
          for pair in "''${pairs[@]}"; do
            name="''${pair%%:*}"
            src="''${pair#*:}"
            if [ ! -f "$src/compatibilitytool.vdf" ]; then
              echo "syncSteamCompatTools: missing compatibilitytool.vdf in $src ($name)" >&2
              exit 1
            fi
          done
          for pair in "''${pairs[@]}"; do
            name="''${pair%%:*}"
            src="''${pair#*:}"
            dest="$compat_dir/$name"
            if [ -L "$dest" ]; then
              rm -f "$dest"
            fi
            mkdir -p "$dest"
            ln -sfn "$src"/* "$dest"/
            for entry in "$dest"/*; do
              [ -e "$entry" ] || [ -L "$entry" ] || continue
              if [ ! -e "$src/$(basename "$entry")" ] && [ ! -L "$src/$(basename "$entry")" ]; then
                rm -rf "$entry"
              fi
            done
            touch "$dest/.nix-managed"
          done
          for d in "$compat_dir"/*/; do
            [ -f "''${d}.nix-managed" ] || continue
            keep=0
            for pair in "''${pairs[@]}"; do
              if [ "$d" = "$compat_dir/''${pair%%:*}/" ]; then
                keep=1
                break
              fi
            done
            if [ "$keep" -eq 0 ]; then
              rm -rf "$d"
            fi
          done
        '';
  };

  services.lact.enable = true;

  environment.systemPackages = with pkgs; [
    lact
    mangohud
    goverlay
    mesa-demos
    lsfg-vk
    gs-run
    winetricks
    bottles-winetricks
    (unstable.bottles.override {
      removeWarningPopup = true;
      extraPkgs = _: [
        lsfg-vk
        gs-run
        winetricks
      ];
    })
    unstable.protonplus
  ];
}
